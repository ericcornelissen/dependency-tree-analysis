#!/bin/bash

## CLI
TOTAL="$1"
PAGE_SIZE="$2"
METRIC="$3"
CLEAN="$4"

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
			"https://packages.ecosyste.ms/api/v1/registries/crates.io/package_names?page=${page}&per_page=${PAGE_SIZE}&sort=${METRIC}" \
			-H 'accept: application/json' \
	)

	tmp=$(echo "${response}" | jq -r '.[]')
	packages="${packages}${tmp}
"
done

echo ''
echo '== DETERMINING TRANSITIVE COUNT =='
counts=''
while IFS= read -r package; do
	rm -rf tmp/
	if [ "${CLEAN}" == 'clean' ]; then
		rm -rf ~/.cargo/git ~/.cargo/registry >/dev/null 2>&1
	fi

	mkdir tmp/
	cd tmp/

  echo "Evaluating '${package}' ..."
	cargo init >/dev/null 2>&1
	if ! timeout 30s cargo add "${package}" >/dev/null 2>&1; then
		echo '  ! crate not resolved'
		cd ..
		continue
	fi

	tmp=$(cargo tree 2>/dev/null)

	version=$(echo "$tmp" | awk 'NR == 2' | awk '{print $3}')
	if [[ -z "${version}" ]]; then
		echo '  ! crate not found'
		cd ..
		continue
	fi

	transitive_count=$(echo "${tmp}" | grep -E '^ ' | wc -l)
	if [[ -z "${transitive_count}" ]]; then
		echo '  ! dependency count could not be determined'
		echo ''
		echo '=== DEBUG START ==='
		echo "${tmp}"
		echo '===  DEBUG END  ==='
		continue
	fi

	echo "  got ${version}"
	echo "  has ${transitive_count} dependencies"

	counts="${counts}${transitive_count}
"

	cd ..
done <<<"${packages}"

echo ''
echo '== COMPUTING STATS =='
sum=0
count=0
while IFS= read -r n; do
	echo "$n"
  sum=$((sum + n))
  count=$((count + 1))
done <<<"$(printf "%s\n" "$counts" | awk 'NF')"

echo ''
echo '== RESULTS =='
echo "avg # deps : $(echo "scale=2; ${sum} / ${count}" | bc) (=${sum}/${count})"
