#!/usr/bin/env bash
# The scheduled job: crawl, export the baseline, write the digest, stage the
# published directory, prune the history, deliver. The variables are the guide's.
set -u
shopt -s nullglob

: "${ARCHIVE:?the archive of the pinned release}"
CONFIG=${CONFIG:-bruce.toml}
DB=${DB:-bruce.duckdb}
PUB=${PUB:-pub}
PUB=${PUB%/}
KEEP=${KEEP-30}
NAME=${NAME:-bruce}
KEEP_VIEWS=${KEEP_VIEWS:-30}
KEEP_JSON=${KEEP_JSON:-400}
DELIVER=${DELIVER:-}

# The first failure's status is the job's, once it has done what it still can.
rc=0
note() { [ "$rc" -ne 0 ] || rc=$1; }

crawl() {
  bruce crawl --config "$CONFIG" --db "$DB"
}

# S1: crawl. A database of another schema (3) is moved aside as the archive,
# replacing the last, and the crawl starts a fresh one. Any other failure stops
# the job with the published directory as it was.
crawl
status=$?
if [ "$status" -eq 3 ]; then
  echo "bruce-nightly: $DB is of another schema version; moved aside as $DB.archive" >&2
  mv -f "$DB" "$DB.archive"
  if [ -e "$DB.wal" ]; then mv -f "$DB.wal" "$DB.archive.wal"; fi
  crawl
  status=$?
fi
[ "$status" -eq 0 ] || exit "$status"

work=$(mktemp -d "$PUB.work.XXXXXX") || exit 1
new=$PUB.new
trap 'rm -rf "$work" "$new"' EXIT
mkdir "$work/digest"

# S2: the run as the baseline, gzipped.
bruce export-baseline --db "$DB" --out "$work/baseline.duckdb" || exit
gzip -n -9 "$work/baseline.duckdb" || exit 1

# S3: the digest, compared with the baseline this job replaces. With none, or
# with one of another schema (3), it is written uncompared. A digest that
# still fails does not stop the job: CI needs the baseline.
digest=3
if [ -f "$PUB/baseline.duckdb.gz" ]; then
  bruce report digest --db "$DB" --out "$work/digest" --name "$NAME" --since "$PUB/baseline.duckdb.gz"
  digest=$?
fi
if [ "$digest" -eq 3 ]; then
  rm -f "$work/digest"/*
  bruce report digest --db "$DB" --out "$work/digest" --name "$NAME"
  digest=$?
fi
[ "$digest" -eq 0 ] || note "$digest"

# Deletes the files given that are dated before the $1 newest nights among them.
trim() {
  local keep=$1 cutoff f d
  shift
  cutoff=$(for f in "$@"; do d=${f##*/}; d=${d#"$NAME"-}; echo "${d:0:10}"; done | sort -ru | sed -n "${keep}p")
  [ -n "$cutoff" ] || return 0
  for f in "$@"; do
    d=${f##*/}; d=${d#"$NAME"-}
    if [[ ${d:0:10} < $cutoff ]]; then rm -f "$f"; fi
  done
}

short() { sha256sum "$1" | cut -c1-16; }

# S4: stage a new directory, then rename it over PUB. SHA256SUMS is written
# last; the files it lists are named by their content.
stage() {
  set -e
  rm -rf "$new"
  mkdir -p "$new/digests"
  cp "$ARCHIVE" "$new/bruce.tar.gz"
  cp "$CONFIG" "$new/bruce.toml"
  cp "$work/baseline.duckdb.gz" "$new/baseline.duckdb.gz"
  local bin=bruce-$(short "$new/bruce.tar.gz").tar.gz
  local cfg=config-$(short "$new/bruce.toml").toml
  local base=baseline-$(short "$new/baseline.duckdb.gz").duckdb.gz
  cp "$new/bruce.tar.gz" "$new/$bin"
  cp "$new/bruce.toml" "$new/$cfg"
  cp "$new/baseline.duckdb.gz" "$new/$base"

  # Last night's set stays one more night, for a fetcher given a stale
  # SHA256SUMS by a cache in front of the directory.
  if [ -f "$PUB/SHA256SUMS" ]; then
    local sum name
    while read -r sum name; do
      case $name in
        bruce-*.tar.gz|config-*.toml|baseline-*.duckdb.gz) cp -p "$PUB/$name" "$new/" || true ;;
      esac
    done < "$PUB/SHA256SUMS"
  fi

  # The dated digests are carried over and tonight's added, under the counts.
  if [ -d "$PUB/digests" ]; then cp -Rp "$PUB/digests/." "$new/digests/"; fi
  local f rest
  if [ "$digest" -eq 0 ]; then
    for f in "$work/digest"/*; do
      cp "$f" "$new/digests/"
      rest=${f##*/}
      rest=${rest#"$NAME"-????-??-??}
      cp "$f" "$new/digest$rest"
    done
  else
    for f in "$PUB"/digest.* "$PUB"/digest-*; do cp -p "$f" "$new/"; done
  fi
  local json=("$new/digests/$NAME"-????-??-??.json) views=()
  for f in "$new/digests/$NAME"-????-??-??[.-]*; do
    case $f in *.json) ;; *) views+=("$f") ;; esac
  done
  trim "$KEEP_JSON" "${json[@]}"
  trim "$KEEP_VIEWS" "${views[@]}"

  (cd "$new" && sha256sum "$bin" "$cfg" "$base" digest.* digest-* digests/*) > "$work/SHA256SUMS"
  cp "$work/SHA256SUMS" "$new/SHA256SUMS"

  rm -rf "$PUB.old"
  if [ -e "$PUB" ]; then mv "$PUB" "$PUB.old"; fi
  mv "$new" "$PUB"
  rm -rf "$PUB.old"
}
( stage )
staged=$?
if [ "$staged" -ne 0 ]; then
  echo "bruce-nightly: staging failed; $PUB is as it was" >&2
  note "$staged"
fi

# S5: prune the history. Staging is done, so a failure here costs no publication.
if [ -n "$KEEP" ]; then
  bruce prune --db "$DB" --keep "$KEEP" || note $?
fi

# S6: deliver.
if [ -n "$DELIVER" ] && [ "$staged" -eq 0 ]; then
  "$DELIVER" "$PUB" || note $?
fi
exit "$rc"
