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

get_rates() {
    maturity=$1
    first=1
    page="euribor-rate-${maturity}"
    file="/tmp/${page}"
    data=$(cat ${file} | grep "By day" -A 10 | grep "<tr><td>")
    while IFS= read -r line; do
        date=$(grep -o -e  "[0-9]\{1,2\}/[0-9]\{1,2\}/[0-9]\{4\}" <<< "$line")
        value=$(grep -o -e "-\?[0-9]\{1,2\}\.[0-9]\{3\}" <<< "$line")
        if [[ -n $date && -n $value ]]; then
            if (( first )); then
                result="$date=$value"
                first=0
            else
                result="$result $date=$value"
            fi
        fi
    done <<< "${data}"
    echo "${result}"
}

last_inserted_time() {
    maturity=$(short_maturity_string $1)
    file="${DATA_PATH}/rate-${maturity}.csv"
    tail -n1 ${file} | cut -d ',' -f 1
}

populate_csv_files() {
    maturity=$(short_maturity_string $1)
    date=$2
    rate=$3
    file="${DATA_PATH}/rate-${maturity}.csv"
    echo "append line '${date},${rate}' to ${file}"
    echo "${date},${rate}" >> ${file}
}

short_maturity_string() {
    maturity=$1
    echo "${maturity}" | tr -d '-' | grep -o -e "[0-9]\{1,2\}[wm]"
}

date_normalized() {
    date=$1
    year=$(echo ${date} | cut -d '/' -f3)
    month=$(echo ${date} | cut -d '/' -f1)
    if [ ${#month} -eq 1 ]; then month="0$month"; fi;
    day=$(echo ${date} | cut -d '/' -f2)
    if [ ${#day} -eq 1 ]; then day="0$day"; fi;
    echo "${year}-${month}-${day}"
}

date_to_epoch() {
  local date=$1
  if date -d "${date}" +%s >/dev/null 2>&1; then
    date -d "${date}" +%s
  else
    date -j -f "%Y-%m-%d" "${date}" +%s
  fi
}

rm -f /tmp/euribor*
summaries=()
# As of November 1st 2013 the number of Euribor rates was reduced to 8 (1-2 weeks, 1, 2, 3, 6, 9 and 12 months).
# As of December 1st 2018 the number of Euribor rates was reduced to 5 (1 week, 1, 3, 6, and 12 months).
for maturity in 1-week 1-month 3-months 6-months 12-months
do
    echo "processing maturity ${maturity}"
    last_inserted=$(last_inserted_time ${maturity})
    fetch_page ${maturity}
    rates=$(get_rates $maturity)
    if [ -z "${rates}" ]; then
        summaries+=("no rates found for ${maturity}")
        echo "no rates found for ${maturity}"
        continue
    fi
    latest_date=$(echo ${rates} | cut -d ' ' -f 1 | cut -d '=' -f1)
    latest_date_normalized=$(date_normalized $latest_date)
    if [ "${last_inserted}" == "${latest_date_normalized}" ]
    then
        summaries+=("rate ${maturity} ignored, data for ${latest_date_normalized} already inserted")
        echo "data for ${latest_date_normalized} already inserted"
        continue
    fi
    # Loop over rates in reverse order
    set -- $rates
    for (( i=$#; i>0; i-- )); do
        key=$(eval "echo \${$i}" | cut -d '=' -f1)
        date=$(date_normalized $key)
        last_inserted_epoch=$(date_to_epoch ${last_inserted})
        date_epoch=$(date_to_epoch ${date})
        if [ ${date_epoch} -le ${last_inserted_epoch} ]; then
            continue
        fi
        rate=$(eval "echo \${$i}" | cut -d '=' -f2)
        populate_csv_files ${maturity} ${date} ${rate}
        summaries+=("inserted rate for ${date} ${maturity}")
    done
done

now=$(date -R)
title="Euribor rates pull at ${now}"
summary=$(IFS=$'\n' eval 'echo "${summaries[*]}"')
notify_pushover "$title" "$summary"