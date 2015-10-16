#! /bin/bash

#uri=`date '+%Y-%m-%d' -d "+1 days"`
#curl -s "http://localhost/titan/api/create_table?date=$uri" > /dev/null 2>&1
#echo "http://localhost/titan/api/create_table?date=$uri"

for cnt in `seq 0 100` 
do    
	dd=`date -d+${cnt}day +%F`
	#echo "curl -XPUT http://10.100.3.213:9200/detail_${dd}" 
	curl -XPUT "http://10.100.3.213:9200/detail_${dd}"
done
