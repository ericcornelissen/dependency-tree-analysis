#!/bin/bash

## CLI
TOTAL="$1"
PAGE_SIZE="$2"
METRIC="$3"

if [[ -z ${TOTAL} || -z ${PAGE_SIZE} || -z ${METRIC} ]]; then
	echo 'USAGE:   ./pipeline.sh <TOTAL> <PAGE_SIZE> <METRIC>'
	echo 'EXAMPLE: ./pipeline.sh 500 100 docker_downloads_count'
	echo ''
	echo ''
	echo '- TOTAL = n * PAGE_SIZE'
	echo '- METRIC in ["downloads", "dependent_repos_count", "docker_dependents_count", "docker_downloads_count"]'
	exit 0
fi


## Main
rm -rf tmp/

echo "Evaluating dependency metrics of top ${TOTAL} Rust (crates.io) crates, based on the metric '${METRIC}'"
echo "Using page size ${PAGE_SIZE}"

echo ''
echo '== COLLECTING PACKAGE NAMES =='
packages=''
pages=$(( (TOTAL + PAGE_SIZE - 1) / PAGE_SIZE ))
for ((page=1; page<=pages; page++)); do
	echo "Fetching page ${page} ..."

	response=$( \
		curl -sX 'GET' \
			"https://packages.ecosyste.ms/api/v1/registries/npmjs.org/package_names?page=${page}&per_page=${PAGE_SIZE}&sort=${METRIC}" \
			-H 'accept: application/json' \
	)

	tmp=$(echo "${response}" | jq -r '.[]')
	packages="${packages}${tmp}"
done

echo ''
echo '== DETERMINING TRANSITIVE COUNT =='
counts=''
while IFS= read -r package; do
	mkdir tmp/
	cd tmp/

  echo "Evaluating ${package} ..."
	cargo init >/dev/null 2>&1
	cargo add "${package}" >/dev/null 2>&1

	tmp=$(cargo tree 2>/dev/null)
	if [[ "$(echo "$tmp" | wc -l)" == "1" ]]; then
		echo '  ! crate not found'
		continue
	fi

	transitive_count=$(echo "${tmp}" | grep -E '^ ' | wc -l)
	counts="${counts}${transitive_count}
"

	echo "  got $(echo "$tmp" | awk 'NR == 2' | awk '{print $3}')"
	echo "  has ${transitive_count} dependencies"

	cd ..
	rm -rf tmp/
done <<<"${packages}"

echo ''
echo '== COMPUTING STATS =='
sum=0
count=0
while IFS= read -r n; do
  sum=$((sum + n))
  count=$((count + 1))
done <<<"${counts}"

echo ''
echo '== RESULTS =='
echo "avg: $((sum / count)) (=${sum}/${count})"
