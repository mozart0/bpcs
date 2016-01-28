#!/bin/bash

# -- 配置 -------
FOLDER="/etc"
STRIP="/"
# -----------------

cd $(dirname "$0")

if [[ "$1" = "init" ]]; then
	php -n -d disable_functions -d safe_mode=Off access.php quickinit
	exit 0
fi

appname=`cat config/appname 2>/dev/null`
atoken=`cat config/access_token 2>/dev/null`
if [[ -z "$appname" || -z "$atoken" ]]; then
	echo "! missing config. try: bash `pwd`/`basename \"$0\"` init"
	exit 1
fi

mkdir -p run
cd run

log_file="_log"
echo '#' $(date '+%F %T') 'start ----------' >> $log_file

today=$(date '+%F')
today_done=${today}_done

if [[ -e $today ]]; then
	test -e $today_done || touch $today_done
	resume=$(wc -l $today_done | cut -f1 -d' ')
	let resume=resume+1
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
echo '-' $(date '+%F %T') "resume=$resume limit=$limit batch=$batch" >> $log_file

counter=$(awk -v url="https://pcs.baidu.com/rest/2.0/pcs/file?method=upload&access_token=${atoken}&ondup=overwrite&path=/apps/bpcs_uploader" '
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
	args = args " -: -kfLsS -X POST --form file=@\"" $0 "\" -w \" %{http_code} %{time_total}\\n\" \"" url substr($0, '${#STRIP}') "\""
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
	echo '-' $(date '+%F %T') "complete $counter" >> $log_file
else
	err=$(cat _err)
	echo '-' $(date '+%F %T') "abort $counter $err" >> $log_file
fi

exit $ret