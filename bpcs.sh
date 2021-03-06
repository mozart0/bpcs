#!/bin/bash

cd $(dirname "$0")

if [[ "$1" = "init" ]]; then
	php -n -d disable_functions -d safe_mode=Off access.php quickinit
	exit 0
fi

[[ -e config.ini ]] && source config.ini
folder=${folder-}
ltrim=${ltrim-/}
lpad=${lpad-}
batch=${batch-200}
retry=${retry-7}
while [[ $1 = *=* ]]; do eval "$1"; shift; done
if [[ -z "$folder" ]]; then
	echo "! missing folder in config.ini"
	exit 1
fi
if ! [[ -e config/access_token ]]; then 
	echo "! missing config folder. try: bash `pwd`/`basename \"$0\"` init"
	exit 1
fi
appname=`cat config/appname`
atoken=`cat config/access_token`

mkdir -p run
cd run

work=$(ls -td *.work 2>/dev/null | head -n1)
if [[ -n "$work" ]]; then
	dest=${work%.work}
	dest_work=$work
	if [[ ! -e "$dest" ]]; then
		echo "! seen $dest_work without $dest"
		exit 1
	fi
else
	dest=$(date '+%F')
	dest_work=${dest}.work
fi

dest_done=${dest}.done
if [[ -e "$dest_done" ]]; then
	echo "! seen $dest_done already"
	exit 1
fi

log_file="_log"
echo '#' $(date '+%F %T') "start $dest ----------" | tee -a $log_file

if [[ -e $dest ]]; then
	touch "$dest_work"
	resume=$(wc -l $dest_work | awk '{print $0+1}')
else
	echo -n > "$dest_work"
	sentry="_sentry"
	sentry_new=${sentry}_new
	touch $sentry_new
	if [[ -e $sentry ]]; then
		find $folder -type f -newer $sentry >> $dest
	else
		find $folder -type f >> $dest
	fi
	mv -f $sentry_new $sentry
	resume=1
fi

ret=0
wait=1
until [[ $retry -eq 0 ]]; do
	echo '-' $(date '+%F %T') "resume=$resume retry=$retry" | tee -a $log_file
	counter=$(awk -v url="https://pcs.baidu.com/rest/2.0/pcs/file?method=upload&access_token=${atoken}&ondup=overwrite&path=/apps/${appname}/${lpad}" '
	function upload(done) {
		if (cc > 0) {
			ret = system("curl " substr(args, 5) " 2>_err >_out")
			if (ret == 0) {
				system("cat _out >> '$dest_work'")
				cc = 0
				args = ""
			} else {
				"sed -n /^{/d _out | wc -l" | getline v
				if (v + 0) system("sed -n /^{/d _out >> '$dest_work'")
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
		args = args " -: -kfLsS -X POST --form file=@\"" $0 "\" -w \" %{http_code} %{time_total}\\n\" \"" url substr($0, '${#ltrim}' + 1) "\""
		counter += 1
		cc += 1
		if (cc == '$batch') upload("batch")
	}
	END {
		if (!ended) upload("end")
	}' $dest)
	ret=$?
	if [[ $ret -eq 0 ]]; then
		echo '-' $(date '+%F %T') "complete $counter" | tee -a $log_file
		mv -f "$dest_work" "$dest_done"
		break
	else
		err=$(cat _err)
		echo '-' $(date '+%F %T') "upload $counter. $err" | tee -a $log_file
		resume=$(wc -l $dest_work | awk '{print $0+1}')
	fi
	let retry--
	sleep $wait
	let wait+=2
done
exit $ret