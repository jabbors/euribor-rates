#!/bin/bash

PUSHOVER_APP_TOKEN=${PUSHOVER_APP_TOKEN:-}
PUSHOVER_USER_KEY=${PUSHOVER_USER_KEY:-}
DATA_PATH=${DATA_PATH:-.}
notify_pushover() {
    title=$1
    body=$2
    if [ -n "$PUSHOVER_APP_TOKEN" ] && [ -n "$PUSHOVER_USER_KEY" ]
    then
        curl -s --form-string "token=$PUSHOVER_APP_TOKEN" --form-string "user=$PUSHOVER_USER_KEY" --form-string "title=$title" --form-string "message=$body" https://api.pushover.net/1/messages.json
    fi
}

fetch_page() {
    maturity=$1
    case $maturity in
        1-week)
            number=5
            ;;
        1-month)
            number=1
            ;;
        3-months)
            number=2
            ;;
        6-months)
            number=3
            ;;
        12-months)
            number=4
            ;;
    esac
    page="euribor-rate-${maturity}"
    file="/tmp/${page}"
    url="https://www.euribor-rates.eu/en/current-euribor-rates/$number/$page/"
    if [ ! -f ${file} ]
    then
        echo "fetching page ${url}"
        curl ${url} -o ${file}
    fi
}

parse_date() {
    maturity=$1
    page="euribor-rate-${maturity}"
    file="/tmp/${page}"
    parsed_date=$(cat ${file} | grep "By day" -A 8 | grep -o -e "[0-9]\{1,2\}/[0-9]\{1,2\}/[0-9]\{4\}" -m 1 | tr '/' '-')
    date_normalized "$parsed_date"
}

parse_rate() {
    maturity=$1
    page="euribor-rate-${maturity}"
    file="/tmp/${page}"
    cat ${file} | grep "By day" -A 8 | grep -o -e "-\?[0-9]\{1,2\}\.[0-9]\{3\}" -m 1
}

last_inserted_time() {
    maturity=$(short_maturity_string $1)
    file="${DATA_PATH}/euribor-rates-${maturity}.csv"
    tail -n1 ${file} | cut -d ',' -f 1
}

populate_csv_files() {
    maturity=$(short_maturity_string $1)
    date=$2
    rate=$3
    file="${DATA_PATH}/euribor-rates-${maturity}.csv"
    echo "append line' ${date},${rate}' to ${file}"
    echo "${date},${rate}" >> ${file}
}

short_maturity_string() {
    maturity=$1
    echo "${maturity}" | tr -d '-' | grep -o -e "[0-9]\{1,2\}[wm]"
}

date_normalized() {
    date=$1
    year=$(echo ${date} | cut -d '-' -f3)
    month=$(echo ${date} | cut -d '-' -f1)
    if [ ${#month} -eq 1 ]; then month="0$month"; fi;
    day=$(echo ${date} | cut -d '-' -f2)
    if [ ${#day} -eq 1 ]; then day="0$day"; fi;
    echo "${year}-${month}-${day}"
}

rm -f /tmp/euribor*
summaries=()
# As of November 1st 2013 the number of Euribor rates was reduced to 8 (1-2 weeks, 1, 2, 3, 6, 9 and 12 months).
# As of December 1st 2018 the number of Euribor rates was reduced to 5 (1 week, 1, 3, 6, and 12 months).
for maturity in 1-week 1-month 3-months 6-months 12-months
do
    echo "processing maturity ${maturity}"
    fetch_page ${maturity}
    date=$(parse_date ${maturity})
    if [ ${#date} -ne 10 ]
    then
        summaries+=("rate ${maturity} skipped" "no date found, something might be wrong")
        echo "no date found, something might be wrong"
        continue
    fi
    rate=$(parse_rate $maturity)
    last_inserted=$(last_inserted_time ${maturity})
    if [ "${last_inserted}" == "${date}" ]
    then
        summaries+=("rate ${maturity} ignored, data for ${date} already inserted")
        echo "data for ${date} already inserted"
        continue
    fi
    populate_csv_files ${maturity} ${date} ${rate}
    summaries+=("inserted rate ${maturity}")
done

now=$(date -R)
last_inserted=$(last_inserted_time 1w)
title="gorates pull at ${now} for ${last_inserted}"
summary=$(IFS=$'\n' eval 'echo "${summaries[*]}"')
notify_pushover "$title" "$summary"