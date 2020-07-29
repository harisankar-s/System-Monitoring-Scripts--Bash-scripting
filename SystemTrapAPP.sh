#!/bin/bash

scriptExcecuteStatus() {
	if (($(ps ax | grep $(basename ${0}) | grep -v grep | wc -l) > 3))
	then
        	echo "$(getTime) WARNING: Since $(basename ${0}) is Already Running Exiting the new Instance."
        	ps aux | grep $(basename ${0}) | grep -v grep
        	exit 0
        fi
}

checkCACHEAlertNotification() {
	if [ ${eventId} = STS_E_1002 ] || [ ${eventId} = STS_E_1004 ] || [ ${eventId} = STS_E_1006 ] || [ ${eventId} = STS_E_1008 ] || [ ${eventId} = STS_E_1010 ]
        then
		cacheAlertOCuuraceCnt=0
		if [ -f ${cacheAlertNotifyFile} ]
		then
        		cacheAlertOCuuraceCnt=$(cat ${cacheAlertNotifyFile})
			cacheAlertOCuuraceCnt=${cacheAlertOCuuraceCnt:-0}
		fi
        	cacheAlertOCuuraceCnt=$(echo ${cacheAlertOCuuraceCnt} + 1 | bc)
		echo ${cacheAlertOCuuraceCnt} > ${cacheAlertNotifyFile}
	fi
	echo "CHECK_CACHING_ALERT :: $eventId $eventName $eventType $errorMessage - ${cacheAlertOCuuraceCnt} - [ THRESHOLD_VALUE - ${cacheAlertThresholdCnt} ]"
}

createALERTFile() {
	eventId="$1"
	eventName="$2"
	errorMessage="$3"
	eventType="$4"
	cacheAlertOCuuraceCnt=0
	cacheAlertNotifyFile=".${eventId}_${eventName}_${eventType}.CACHE"
	ipAddress=$(/sbin/ifconfig | grep "inet addr:" | grep -v "127.0.0.1" | awk '{print $2}' | awk -F':' '{print $2}' | head -1)
	fileName="${statusFilePath}/$(/bin/hostname)_${eventName}"
	eventName="${eventName}: $(/bin/hostname) (${ipAddress})"
	if [ "${eventType}" = HIGH ]
	then
		delimiter="GENERIC"
	else
		delimiter="MESSAGE"
	fi
	checkCACHEAlertNotification
	if ((cacheAlertOCuuraceCnt == 0)) || ((cacheAlertOCuuraceCnt >  cacheAlertThresholdCnt))
	then
		rm -f "${cacheAlertNotifyFile}"
		echo "SENDING THE EVENT :: $eventName - $eventId - $eventType - $errorMessage [ $cacheAlertOCuuraceCnt ]"
		echo "${eventName}" > "${fileName}.${delimiter}"
		echo "${errorMessage}" >> "${fileName}.${delimiter}"
		echo "${notificationEmail}" >> "${fileName}.${delimiter}"
	else
		echo "CACHING_THE_EVENT :: $eventName - $eventId - $eventType - $errorMessage :: [ OCCURANCE_VALUE - ${cacheAlertOCuuraceCnt} <> THRESHOLD_VALUE - ${cacheAlertThresholdCnt} ]"
		rm -f "${statusFile}"
	fi
}

checkAlertSENDStatus() {
	statusFile="$1"
	eventId="$2"
	eventName="$3"
	errorMessage="$4"
	eventType="$5"
	if [ -f "${statusFile}" ] && [ -s "${statusFile}" ]
	then
		preStatus=$(cat "${statusFile}")
		if [ "${preStatus}" = HIGH ]
		then
			echo "[NORMAL_EVENT]_________________________ $errorMessage _________________________"
			createALERTFile "${eventId}" "${eventName}" "${errorMessage}" "${eventType}"
		fi
		rm -f "${statusFile}"
	fi
}

checkMysqlConnectivityStatus() {
	mysqlPort=$1
	eventId="STS_E_1012"
	eventType="EVENT"
	ipAddress=127.0.0.1
	eventName="MYSQLACCESSSTATUS-${mysqlPort}"
	statusFile=".${mysqlPort}_MysqlStatus"
	connectStatus=$(echo > /dev/tcp/${ipAddress}/"${mysqlPort}" >/dev/null 2>&1 && echo 1 || echo 0) 2>&1

	if ((connectStatus == 0 ))
	then
		errorMessage="Mysql Server with Port ${mysqlPort} went Down on ${ipAddress} ($(/bin/hostname))."
		echo "[CRITICAL_EVENT] $errorMessage"
		echo HIGH > "$statusFile"
		eventType="HIGH"
		createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
	else
		eventId="STS_E_1013"
		errorMessage="Mysql Server with Port ${mysqlPort} Came Up on ${ipAddress} ($(/bin/hostname))."
		eventType="LOW"
		checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
	fi
}

checkMysqlLockMGNR() {
	mysqlPort="${1}"
	checkMysqlConnectivityStatus "${mysqlPort}"

	if ((connectStatus > 0))
	then
		eventId="STS_E_1017"
		eventName="MYSQLLOCKMANAGER"
		eventType="EVENT"
		statusFile=".MysqlLockStatus${mysqlPort}"
		mysqlLockCnt=$(${TIMEOUT} mysql -uroot -proot -h127.0.0.1 -P"${mysqlPort}" -Ae "SHOW FULL PROCESSLIST;" | grep -v grep | grep -ic LOCK)
		#mysqlLockCnt=1

		if ((mysqlLockCnt > 0))
		then
			warning="Mysql Lock Table is Reached to Threshold Limit at instance ${mysqlPort} in ${ipAddress} ($(/bin/hostname)) and total Lock table is ${mysqlLockCnt}."
			echo "[CRITICAL_EVENT] ${warning}"
			errorMessage=${warning}
			echo HIGH > "$statusFile"
			eventType="HIGH"
			createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
		else
			eventId="STS_E_1018"
			errorMessage="Mysql Lock table Usage of ${ipAddress} ($(/bin/hostname)) at  instance ${mysqlPort} is Recovered to Normal Usage Limit..."
			eventType="LOW"
			checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
		fi
	fi
}

checkMysqlConnectionMGNR() {
	mysqlPort=${1}
	mysqlIniFile="${2}"
	eventId="STS_E_1014"
	eventName="MYSQLCONNMANAGER"
	eventType="EVENT"
	statusFile=".MysqlConnStatus${mysqlPort}"
	if [ -f "${mysqlIniFile}" ] && [ -s "${mysqlIniFile}" ]
	then
		cnt=$(${TIMEOUT} cat "${mysqlIniFile}" | grep -v grep | grep -c max_connection)
		if ((cnt > 0))
		then
			maxConn=$(${TIMEOUT} cat "${mysqlIniFile}" | grep max_connections | awk -F'=' '{print $2}')
			timeWtConn=$(${TIMEOUT} netstat -antp | grep ":${mysqlPort}" | grep -v grep | grep -c TIME_WAIT)
			closeWtConn=$(${TIMEOUT} netstat -antp | grep ":${mysqlPort}" | grep -v grep | grep -c CLOSE_WAIT)
			estConn=$(${TIMEOUT} netstat -antp | grep ":${mysqlPort}" | grep -v grep | grep -c ESTABLISHED)
			
			if ((timeWtConn > maxConn)) || ((closeWtConn > maxConn)) || ((estConn > maxConn))
			then
				if ((timeWtConn > maxConn))
				then
					noConn=$timeWtConn
				elif ((closeWtConn > maxConn))
				then
					noConn=$closeWtConn
				elif ((estConn > maxConn))
				then
					noConn=$estConn
				fi
				errorMessage="Number of MYSQL Connections on ${mysqlPort} Exceeds Configured Limit, Connections $noConn in ${ipAddress} ($(/bin/hostname))."
				echo "[CRITICAL_EVENT] ${errorMessage}"
				echo HIGH > "${statusFile}"
				eventType="HIGH"
				createALERTFile "$eventId" "$eventName" "${errorMessage}" "$eventType"
				else
				eventId=STS_E_1015
				errorMessage="Number of MYSQL Connections on ${mysqlPort} Limited to Normal Configured Limit in ${ipAddress} ($(/bin/hostname))."
				eventType="LOW"
				checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "${errorMessage}" "$eventType"
			fi
		fi
	fi
}

checkMysqlReplicationMGNR() {
	mysqlPort="${1}"
	checkMysqlConnectivityStatus "${mysqlPort}"
	if ((connectStatus > 0))
	then
		eventId="STS_E_1016"
		eventName="REPLICATIONSTATUS"
		eventType="EVENT"
		statusFile=".ReplicationStatus${mysqlPort}"

		dbUserName=root
		dbPasswd=root
		dbIPAdd=127.0.0.1
		dbPort=${mysqlPort}
		timeStamp="[ $(date '+%d-%m-%Y %H:%M:%S') ]"
		mysql -u${dbUserName} -p${dbPasswd} -h${dbIPAdd} -P"${dbPort}" -A -e "show slave status\G;" > "${statusFile}Info"
		slaveIOStatus=$(< "${statusFile}Info" grep Slave_IO_Running: | awk -F':' '{print $2}' | sed -e 's/ //g')
		slaveSQLStatus=$(< "${statusFile}Info" grep Slave_SQL_Running: | awk -F':' '{print $2}' | sed -e 's/ //g')
		#lastErrMsg=$(< "${statusFile}Info" grep Last_Error | awk -F'Last_Error: ' '{print $2}')
		#lastSqlErr=$(< "${statusFile}Info" grep Last_SQL_Error | awk -F'Last_SQL_Error: ' '{print $2}')
		#secBehingMstr=$(< "${statusFile}Info" grep Seconds_Behind_Master: | awk -F'Seconds_Behind_Master: ' '{print $2}' | sed -e 's/ //g')
		slaveIOStatus=$(echo "${slaveIOStatus}" | tr "[:lower:]" "[:upper:]")
		slaveSQLStatus=$(echo "${slaveSQLStatus}" | tr "[:lower:]" "[:upper:]")
		if [ "${slaveIOStatus}" = "NO" ] || [ "${slaveSQLStatus}" = "NO" ]
		then
			errorMessage="REPLICATION Breaks at ${timeStamp} in DB SERVER having IP ${ipAddress} ($(/bin/hostname)) with Port ${dbPort}."
			echo "[CRITICAL_EVENT] ${errorMessage}"
			echo HIGH > "$statusFile"
			eventType="HIGH"
			createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"        
		else
			eventId="STS_E_1017"
			errorMessage="Replication Came Up on ${ipAddress} ($(/bin/hostname)) with  Port ${dbPort}."
			eventType="LOW"
			checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
		fi
		rm -f "${statusFile}Info"
	fi
}

#===========================================================================================================================================================#

scriptExcecuteStatus
TIMEOUT="timeout 10s"
. $(${TIMEOUT} find ~/ -maxdepth 1 -mindepth 1 -type f -name '.bash_profile')
if (($? > 0))
then
	exit 0
fi
statusFilePath="${HOME}/.ONM_STATUS/"
statusFilePath=/home/cmsuser/.ONM_STATUS/
mkdir -p ${statusFilePath}

systemDISCUsageThresholdLimit=90
systemMEMORYUsageThresholdValue=90
systemCPUUsageThresholdValue=90
systemCPULoadAverageThresholdValue=16
appCPUUsgThresholdValue=400
appMEMORYUsgThresholdValue=90

highAlertNotifyThresholdLimit=95
isHighAlertThresholdLimit=false
notificationEmail=""
cacheAlertThresholdCnt=5

systemCPULoadAverageThresholdValue=$(cat /proc/cpuinfo | grep -w processor | wc -l)	
ipAddress=$(${TIMEOUT} /sbin/ifconfig| grep "inet addr:" | grep -v "127.0.0.1" | awk '{print $2}' | awk -F':' '{print $2}' | head -1)

declare $(${TIMEOUT} df -Ph | awk -v highAlertNotify=${highAlertNotifyThresholdLimit} {'if ( NR >1 ) {sub("%","",$5); if ($5 >= highAlertNotify) {print "isHighAlertThresholdLimit=true"; exit} else {print "isHighAlertThresholdLimit=false"} }'})
warning=$(${TIMEOUT} df -Ph | awk -v size=$systemDISCUsageThresholdLimit {'if ( NR >1 ) {sub("%","",$5); if ($5 >= size) {printf("%s is Reached Threshold Limit and Percentage Value is %s%.\n",$6,$5)}}'})
echo $warning
eventId="STS_E_1000"
eventName="DISCMANAGER"
eventType="EVENT"
statusFile=".DiscStatus"
if ((${#warning} > 1))
then
	echo "[CRITICAL_EVENT] ${warning}"
	if ($isHighAlertThresholdLimit)
	then
		errorMessage="DISC Usage of ${ipAddress} ($(/bin/hostname)) is Critical. "${warning}
		notificationEmail="[TO:highalert@6dtech.co.in,adarsh.rs@6dtech.co.in]"
	else
		errorMessage="DISC Usage of ${ipAddress} ($(/bin/hostname)) is Critical. "${warning}
		notificationEmail=""
	fi
	echo HIGH > "$statusFile"
	eventType="HIGH"
	createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
	eventId="STS_E_1001"
	errorMessage="Disc Space Usage of ${ipAddress} ($(/bin/hostname)) is Recoved to Normal Usage Limit..."
	eventType="LOW"
	checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi

usedMememory=$(${TIMEOUT} /usr/bin/free -m | grep 'buffers/cache:' | awk '{print $3}' | sed -e 's/ //g')
freeMememory=$(${TIMEOUT} /usr/bin/free -m | grep 'buffers/cache:' | awk '{print $4}' | sed -e 's/ //g')
totMememory=$(echo $usedMememory + $freeMememory | bc)

percntageUsage=$(echo $usedMememory \* 100 / $totMememory | bc)
eventId="STS_E_1002"
eventName="MEMORYMANAGER"
eventType="EVENT"
statusFile=".MemStatus"
if ((percntageUsage >= systemMEMORYUsageThresholdValue))
then
	warning="Memory Utilization is Reached to Threshold Limit in ${ipAddress} ($(/bin/hostname)) and Utilization Percentage Value is $percntageUsage%."
	echo "[CRITICAL_EVENT] ${warning}"
	errorMessage=${warning}
	echo HIGH > "$statusFile"
	eventType="HIGH"
	createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
	eventId="STS_E_1003"
	errorMessage="Memory Usage of ${ipAddress} ($(/bin/hostname)) is Recoved to Normal Usage Limit..."
	eventType="LOW"
	checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi

cpuInfo=$(${TIMEOUT} top -b -n1 |awk 'NR>2 && NR<4 {print $0}' | awk -F':' '{print $2}')
cpuIdleUsage=$(echo "$cpuInfo" | awk -F',' '{print $4}' | awk -F'.' '{print $1}' | sed -e's/%id//g')
cpuUsage=$(echo 100 - $cpuIdleUsage | bc)
eventId="STS_E_1004"
eventName="CPUMANAGER"
eventType="EVENT"
statusFile=".CpuUsageStatus"
if ((cpuUsage >= systemCPUUsageThresholdValue))
then
	warning="CPU Utilization is Reached to Threshold Limit in ${ipAddress} ($(/bin/hostname)) and Utilization Percentage Value is $cpuUsage%."
	echo "[CRITICAL_EVENT] ${warning}"
	errorMessage=${warning}
	echo HIGH > "$statusFile"
	eventType="HIGH"
	createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
	eventId="STS_E_1005"
	errorMessage="CPU Usage of ${ipAddress} ($(/bin/hostname)) is Recoved to Normal Usage Limit..."
	eventType="LOW"
	checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi

cpuLoadInfo=$(${TIMEOUT} top -b -n1 |awk 'NR>0 && NR<2 {print $0}' | awk -F',' '{print $(NF-2)","$(NF-1)","$(NF)}' | awk -F':' '{print $2}' | sed 's/^ //g' | sed 's/ $//g')
oneCpuLoad=$(echo "$cpuLoadInfo" | awk -F',' '{print $1}' | awk -F'.' '{print $1}')
fiveCpuLoad=$(echo "$cpuLoadInfo" | awk -F',' '{print $2}' | awk -F'.' '{print $1}')
fifCpuLoad=$(echo "$cpuLoadInfo" | awk -F',' '{print $3}' | awk -F'.' '{print $1}')
eventId="STS_E_1006"
eventName="CPUMANAGER"
eventType="EVENT"
statusFile=".CpuLoadStatus"
if (((fiveCpuLoad >= systemCPULoadAverageThresholdValue)) && ((fifCpuLoad >= systemCPULoadAverageThresholdValue))) || (((oneCpuLoad >= systemCPULoadAverageThresholdValue)) && ((fiveCpuLoad >= systemCPULoadAverageThresholdValue)))
then
	warning="CPU LOAD Utilization is Reached to Threshold Limit in ${ipAddress} ($(/bin/hostname)) and Utrilization Values are CPU LOAD AVERAGE : $cpuLoadInfo."
	echo "[CRITICAL_EVENT] ${warning}"
	errorMessage=${warning}
	echo "HIGH" > "$statusFile"
	eventType="HIGH"
	createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
	eventId="STS_E_1007"
	errorMessage="CPU LOAD Usage of ${ipAddress} ($(/bin/hostname)) is Recoved to Normal Usage Limit..."
	eventType="LOW"
	checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi

warning=$(${TIMEOUT} top -b -n1 | awk 'NR>6 {print $0}' | awk -v size=$appMEMORYUsgThresholdValue {'if (($10 >= size)) {printf("Module %s with Pid %s Reached Threshold Limit and Usage is %s%. ",$12,$1,$10)}'})
eventId="STS_E_1008"
eventName="MEMORYMANAGER"
eventType="EVENT"
statusFile=".AppMemStatus"
if  ((${#warning} > 1))
then
	echo "[CRITICAL_EVENT] ${warning}"
	errorMessage="Application Memory Usage is Critical in ${ipAddress} ($(/bin/hostname)) "${warning}
	echo "$errorMessage"
	echo "HIGH" > "$statusFile"
	eventType="HIGH"
	createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
	eventId="STS_E_1009"
	errorMessage="Memory Usage of Application Module in ${ipAddress} ($(/bin/hostname)) is Recoved to Normal Usage Limit..."
	eventType="LOW"
	checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi

warning=$(${TIMEOUT} top -b -n1 | awk 'NR>6 {print $0}' | awk -v size=$appCPUUsgThresholdValue {'if ($9 >= size) {printf("Module %s with Pid %s Reached Threshold Limit and Usage is %s%. ",$12,$1,$9)}'})
eventId="STS_E_1010"
eventName="CPUMANAGER"
eventType="EVENT"
statusFile=".AppCpuStatus"
if ((${#warning} > 1))
then
	echo "[CRITICAL_EVENT] ${warning}"
	errorMessage="Application CPU Usage is Critical in ${ipAddress} ($(/bin/hostname)) "${warning}
	echo "$errorMessage"
	echo "HIGH" > "$statusFile"
	eventType="HIGH"
	createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
	eventId="STS_E_1011"
	errorMessage="CPU Usage of Application Modules in ${ipAddress} ($(/bin/hostname)) is Recoved to Normal Usage Limit..."
	eventType="LOW"
	checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi

#eventId="STS_E_1012"
#eventName="APPMANAGERSTATUS"
#eventType="EVENT"
#statusFile=".AppManagerStatus"
#cnt=`ps -Aef | grep -i PROCESSMGNR | grep -v grep | wc -l`

#if (($cnt == 0 ))
#then
#        errorMessage="Application Manager (PROCESSMGNR) is Down on ${ipAddress} ($(/bin/hostname))."
#        echo "[CRITICAL_EVENT] $errorMessage"
#        echo HIGH > "$statusFile"
#        eventType="HIGH"
#        createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
#else
#        eventId="STS_E_1013"
#        errorMessage="Application Manager (PROCESSMGNR) Came Up on ${ipAddress} ($(/bin/hostname))."
#        eventType="LOW"
#        checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
#fi

<<comment
checkMysqlLockMGNR 3308

checkMysqlConnectionMGNR 3306 "/etc/my.cnf"
checkMysqlConnectionMGNR 3307 "/etc/my1.cnf"
checkMysqlConnectionMGNR 3308 "/etc/my2.cnf"
checkMysqlConnectionMGNR 3309 "/etc/my3.cnf"

checkMysqlReplicationMGNR 3306
checkMysqlReplicationMGNR 3307
checkMysqlReplicationMGNR 3308
comment

nestatStaticsUIPORTAL=$(${TIMEOUT} netstat -antp | egrep -v "ESTABLISHED|LISTEN" | awk '$4 ~ /:80$/ ||  $4 ~ /:16080$/ {print $0}' | wc -l)
if ((${nestatStaticsUIPORTAL} > 50))
then
        eventId="STS_E_1014"
        eventName="NETWORKMANAGER"
        eventType="EVENT"
        statusFile=".AppNetworkStatus"
        warning="Abnormality observed on TCP Connections WAIT state on Digimate UI portal end point URL on ${ipAddress} ($(/bin/hostname))."
        timewaitCount=$(${TIMEOUT} netstat -antp | egrep "TIME_WAIT" | awk '$4 ~ /:80$/ ||  $4 ~ /:16080$/ {print $0}' | wc -l)
        finwaitCount=$(${TIMEOUT} netstat -antp | egrep "FIN_WAIT" | awk '$4 ~ /:80$/ ||  $4 ~ /:16080$/ {print $0}' | wc -l)
        otherCount=$(${TIMEOUT} netstat -antp | egrep -v "ESTABLISHED|LISTEN|TIME_WAIT|FIN_WAIT" | awk '$4 ~ /:80$/ ||  $4 ~ /:16080$/ {print $0}' | wc -l)
        warning="${warning}\nTIME_WAIT :: ${timewaitCount} \n FIN_WAIT :: ${finwaitCount} \n OTHER_WAIT :: ${otherCount}"
	#warning="${warning}\n$(${TIMEOUT} netstat -antp | awk '$4 ~ /:80$/ ||  $4 ~ /:16080$/ {print $0}')"
	#echo "${eventName} :: ${eventType} :: ${warning}"
fi
if ((${#warning} > 1))
then
        echo "[CRITICAL_EVENT] ${warning}"
        errorMessage=${warning}
        echo "HIGH" > "$statusFile"
        eventType="HIGH"
        createALERTFile "$eventId" "$eventName" "$errorMessage" "$eventType"
else
        eventId="STS_E_1011"
        nestatStaticsUIPORTAL=$(${TIMEOUT} netstat -antp | egrep -v "ESTABLISHED|LISTEN" | awk '$4 ~ /:80$/ ||  $4 ~ /:16080$/ {print $0}' | wc -l)
        errorMessage="Recoverd TCP Connections WAIT state on Digimate UI portal ${ipAddress} ($(/bin/hostname)). Current WAIT States count :: ${nestatStaticsUIPORTAL}"
        eventType="LOW"
        checkAlertSENDStatus "$statusFile" "$eventId" "$eventName" "$errorMessage" "$eventType"
fi


destIP=10.3.60.4
destPath=/data/MONITORINGTOOL/.ONM_STATUS
hostName="*.*"

cd "${statusFilePath}"
for statusFile in $(find . -maxdepth 1 -type f -name "${hostName}" | sed 's/.\///g')
do
	mv "${statusFile}" "Airtel-Digimate_${statusFile}"
done

fileName="${statusFilePath}"/Airtel-Digimate_*
ls -ltrh "${fileName}"
lftp -e "set cmd:fail-exit yes; set net:reconnect-interval-base 60; set net:max-retries 1; cd ${destPath}; mput -E $fileName; mput -E ${statusFilePath}/*; quit" -u digimate,'D!g!mat3' sftp://$destIP
rm -f "$fileName" "${statusFilePath}"/*
