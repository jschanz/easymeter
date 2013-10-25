!/bin/sh
date_long=`date +"%Y-%m-%d_%H:%M:%S"`
date_short=`date +"%H:%M"`
date_log=`date +"%Y%m%d"`
url="192.168.178.28/index.html"

# curl -s http://server305vmx.mueller.de | grep -A 1 "akt_leistung" | tail -1 | sed "s/W//g" | sed "s/^[ ]*/$date_long;$date_short;/g" 
POWER=`curl -s http://server305vmx.mueller.de | grep -A 1 "akt_leistung" | tail -1 | sed "s/W//g" | sed "s/^[ ]*/$date_short;/g" | tee -a $date_log.csv`
ACTUAL_POWER=`echo $POWER | awk -F";" '{ print $2 }'`

# doku beispiel
# curl -d "d=20111201" -d "t=10:00" -d "v1=1000" -d "v2=150" -H "X-Pvoutput-Apikey: Your-API-Key" -H "X-Pvoutput-SystemId: Your-System-Id" http://pvoutput.org/service/r2/addstatus.jsp
curl -d "d=date_log" -d "date_short" -d "v4=$ACTUAL_POWER" -H "X-Pvoutput-Apikey: fsdfsdoh2131243m" -H "X-Pvoutput-SystemId: 12345" http://pvoutput.org/service/r2/addstatus.jsp
