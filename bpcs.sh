#!/bin/bash

# -- configs ------
# target_path = LPAD + slice($fullpath, strlen(LTRIM))
FOLDER="/private/etc"
LTRIM="/private/"
LPAD=""
# -----------------

cd $(dirname "$0")

if [[ "$1" = init ]]; then
	php -n -d disable_functions -d safe_mode=Off access.php quickinit
	exit 0
fi

if ! [[ -e config/access_token ]]; then 
	echo "! missing config. try: bash `pwd`/`basename \"$0\"` init"
	exit 1
fi

if [[ "$1" = resume ]] && [[ -s "$2" ]]; then
	today="$2"
	shift
	shift
else
	today=$(date '+%F')
fi
today_done=${today}_done

echo "- $today $today_done"
exit 0

appname=`cat config/appname`
atoken=`cat config/access_token`

mkdir -p run
cd run

log_file="_log"
echo '#' $(date '+%F %T') "start $today ----------" | tee $log_file

if [[ -e $today ]]; then
	touch $today_done
	resume=$(wc -l $today_done | awk '{print $0+1}')
else
	rm -f $today_done
	sentry="_sentry"
	sentry_new=${sentry}_new
	touch $sentry_new
	if [[ -e $sentry ]]; then
		find $FOLDER -type f -newer $sentry >> $today
	else
		find $FOLDER -type f >> $today
	fi
	mv -f $sentry_new $sentry
	resume=1
fi

limit=${1-0}
batch=${2-200}
retry=${3-10}

while [[ $retry -ge 0 ]]; do
	echo '-' $(date '+%F %T') "resume=$resume limit=$limit batch=$batch retry=$retry" | tee $log_file
	counter=$(awk -v url="https://pcs.baidu.com/rest/2.0/pcs/file?method=upload&access_token=${atoken}&ondup=overwrite&path=/apps/${appname}/${LPAD}" '
	function upload(done) {
		if (cc > 0) {
			ret = system("curl " substr(args, 5) " 2>_err >_out")
			if (ret == 0) {
				system("cat _out >> '$today_done'")
				cc = 0
				args = ""
			} else {
				"sed -n /^{/d _out | wc -l" | getline v
				if (v + 0) system("sed -n /^{/d _out >> '$today_done'")
				print counter - cc + v
				ended = 1
				exit ret
			}
		}
		if (done != "batch") {
			print counter + 0
			ended = 1
			exit 0
		}
	}
	(NR >= '$resume') {
		args = args " -: -kfLsS -X POST --form file=@\"" $0 "\" -w \" %{http_code} %{time_total}\\n\" \"" url substr($0, '${#LTRIM}' + 1) "\""
		counter += 1
		cc += 1
		if (cc == '$batch') upload("batch")
		if (counter == '$limit') upload("limit")
	}
	END {
		if (!ended) upload("end")
	}' $today)
	ret=$?
	if [[ $ret -eq 0 ]]; then
		echo '-' $(date '+%F %T') "complet $counter" | tee $log_file
		break
	else
		err=$(cat _err)
		echo '-' $(date '+%F %T') "abort $counter $err" | tee $log_file
		resume=$(wc -l $today_done | awk '{print $0+1}')
		let retry--
	fi
done

exit $ret