#!/bin/bash
#Define your variables here
status_path="/path/to/this/file/"
discord_webhook="YOUR_DISCORD_WEBHOOK_HERE"


#Get the list of container ids
inspect_results=`docker stats --no-stream`
inspect_results="${inspect_results:130}"
container_ids=`echo $inspect_results|sed 's/\ /\n/14;P;D'|awk '{print $1}'`

#initialize things as zero or null
java_spawn_state=0
bedrock_spawn_state=0
bedrock_string=$(jq -n '' )
java_string=$(jq -n '' )
date_=`date|sed 's/:/;/g'`

#loop through those container ids and find the Minecraft ones
for token in $container_ids;
do
	inspection=`docker inspect "$token"`
	is_it_bedrock=`echo $inspection|grep "bedrock"`
	is_it_java=`echo $inspection|grep "server.jar"`

###BEDROCK###
	#see if we found those containers by checking if the is_it variables are null or zero length.  If they aren't, we found them!
	if [ -z "$is_it_bedrock" ]; then
		:
	else
		#here, replace those commas with newlines to make it easier to read; then remove all non-standard characters. Lastly, find the spawns/disconnects
	        bedrock_id=`echo $is_it_bedrock|sed 's/,/\n/g'|grep "Id"|tr -d '"'|awk '{print $4}'`
                bedrock_log=`cat -v /var/lib/docker/containers/$bedrock_id/local-logs/container.log|tr -d '\0^M@'|sed 's/stdout/\n/g'`
		bedrock_join_leave=`echo "$bedrock_log"|grep -e "Spawned" -e "disconnected"`

		#alright, we got the entries that show the spawns and disconnects.  Let's iterate through it and figure out who is in what status
		for i in $bedrock_join_leave;
		do
			#are they logged in or not? Notice the order of the loop here. The first time through, we will never get a true
			#that is because once we find the keyword spawned or disconnect, the NEXT entry will be the player.  We want that entry
			if [ $bedrock_spawn_state == 1 ]; then
                                bedrock_string=$(echo $bedrock_string | jq '."'$i'" = "Joined the game!"')
				bedrock_spawn_state=0
				#our work is done here; reset the state back to zero and initialize the JSON with the player name and statements
			fi

                        if [ $bedrock_spawn_state == 2 ]; then
				j=`echo $i | tr -d ','`
                                bedrock_string=$(echo $bedrock_string | jq '."'$j'" = "Left the game!"')
                                bedrock_spawn_state=0
                        fi

			#find occurences of connects and disconnects
			if [ $i = "Spawned:" ]; then
				bedrock_spawn_state=1
			fi

			if [ $i = "disconnected:" ]; then
				bedrock_spawn_state=2
			fi
		done
	fi

###JAVA###
        if [ -z "$is_it_java" ]; then
                :
        else
	        java_id=`echo $is_it_java|sed 's/,/\n/g'|grep "Id"|tr -d '"'|awk '{print $4}'`
        	java_log=`cat -v /var/lib/docker/containers/$java_id/local-logs/container.log|tr -d '\0^M@'`
		java_join_leave=`echo "$java_log"|grep -e "joined" -e "left"`

                for i in $java_join_leave;
                do
                        #find occurences of connects and disconnects
                        if [ $i = "joined" ]; then
                                java_spawn_state=1
                        fi

                        if [ $i = "left" ]; then
                                java_spawn_state=2
                        fi

                        #are they logged in or not?
                        if [ $java_spawn_state == 1 ]; then
                                java_string=$(echo $java_string | jq '."'$j'" = "Joined the game!"')
                                java_spawn_state=0
                        fi

                        if [ $java_spawn_state == 2 ]; then
                                k=`echo $j | tr -d ','`
                                java_string=$(echo $java_string | jq '."'$k'" = "Left the game!"')
                                java_spawn_state=0
                        fi

			#we need to keep this variable from the previous loop value for usage since the username is BEFORE the trigger
			j=$i
                done

        fi
done

#write our current status to a temp file and let's compare to the previous.  If it is different (returns false), we can do something
echo $bedrock_string > ${status_path}bedrock.status.tmp
echo $java_string > ${status_path}java.status.tmp
bedrock_action=`jq '. == $other' < ${status_path}bedrock.status.tmp --argfile other ${status_path}bedrock.status`
java_action=`jq '. == $other' < ${status_path}java.status.tmp --argfile other ${status_path}java.status`


if [ $bedrock_action = "true" ]; then
	if [ $java_action = "true" ]; then
		#if neither java nor bedrock have changed, just leave. No use wasting time
	 	exit 1
	fi
fi

#but if they HAVE changed...
if [ $bedrock_action = "false" ]; then
	bedrock_body=`jq -n '
		input as $f1 | input as $f2
		| reduce ($f1|keys_unsorted[]) as $k ({};
		if $f2 | has($k) and $f1[$k] != $f2[$k] then .[$k]=$f1[$k] else . end)
		' ${status_path}bedrock.status.tmp ${status_path}bedrock.status`
	bedrock_body=`echo $bedrock_body $date_ | tr -d '{:}"'`
	curl -H "Content-Type: application/json" -d '{"username": "Minecraft_Alerter (BEDROCK)", "content": "'"$bedrock_body"'"}' "${discord_webhook}"
	echo $bedrock_string > ${status_path}bedrock.status
fi

if [ $java_action = "false" ]; then
        java_body=`jq -n '
                input as $f1 | input as $f2
                | reduce ($f1|keys_unsorted[]) as $k ({};
                if $f2 | has($k) and $f1[$k] != $f2[$k] then .[$k]=$f1[$k] else . end)
                ' ${status_path}java.status.tmp ${status_path}java.status`
        java_body=`echo $java_body $date_ | tr -d '{:}"'`
        curl -H "Content-Type: application/json" -d '{"username": "Minecraft_Alerter (JAVA)", "content": "'"$java_body"'"}' "${discord_webhook}"
        echo $java_string > ${status_path}java.status
fi
#Pack it up boys! We are done here!

