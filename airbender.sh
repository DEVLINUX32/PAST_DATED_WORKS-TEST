#!/bin/bash
###|=================================================================================================================================================================================================
###|SCRIPT_PATH                          :  /usr/lib/lua/luci/ap/airbender.sh
###|USAGE                                :  to get acsreport for 2.4ghz and 5ghz radios for airbender and then make json to sent to cloud via mqtt
###|OTHER_FILES_CREATION_AND_DEPENDENCY  :  acsreport_2_4ghz,acsreport_2_4ghz.json,acsreport_5ghz,acsreport_5ghz.json
###|ALGORITHM-WORKFLOW                   :  1) Generate AcsReports for both 2.4Ghz and 5ghz that contains information like channel_load and neigbour ap-information
###|"________________"                   :  2) Than make and store data in json file and send to cloud via mqtt.
###|SUPPORT                              :  Only work/tested for qsdk model aps ~[H-245.*|O-230.*|I-240.*|O-240.*|H-250.*|I-270.*|I-280.*|I-290.*|O-290.*|I-470.*|I-480.*|O-480.*|I-490.*|O-490.*]
###|ARGUMENTS                            :  sh /usr/lib/lua/luci/ap/airbender.sh "ChanInfo/Neighbors"
###|==================================================================================================================================================================================================
######################################################################################################################################################################################################

###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
###GLOBAL VARIABLES,AND FILES LOCATIONS
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
airbender_directory="/tmp/all_spectrumdata/airbender_data"      ###all data will be processed and stored in "/tmp/" only[memory-safe]
mkdir -p "$airbender_directory"
mkdir -p "/tmp/Rf_spectral_logfiles";
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
###CHECK-FOR-REQUIRED-PACKAGES
if [ ! -x "/usr/bin/tee" ] || [ ! -x "/usr/bin/timeout" ]; then
    if [ ! -x "/usr/bin/tee" ]; then
        echo "tee is not installed in /usr/bin.";
    fi
    if [ ! -x "/usr/bin/timeout" ]; then
        echo "timeout is not installed in /usr/bin.";
    fi
    exit 0;
fi
###/K_FILE") 2> /dev/null;  ###LOCK CONDITION CHECK
then
    trap 'rm -f "$LOCK_FILE"; exit $?' INT TERM EXIT
            ###//////////////////////////////////////////////
            ###GLOBAL VARIABLES,FUNCTIONS AND FILES LOCATION
            ###//////////////////////////////////////////////
            mac=$(ifconfig br-wan | head -n1 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}');  formatted_date=$(date +"%d-%m-%Y %I:%M:%S %p");
            action_name_2_4ghz_channel_utilization="ChanInfoOnDemand";  action_name_2_4_ghz_wid="NeighborsOnDemand";
            adjusted_interfacename_2_4ghz="wifi0"       ###to make ath00 named as wifi0 for cloud understanding for 2.4ghz
            airbender_directory="/tmp/all_spectrumdata/airbender_data"      ###all data will be processed and stored in "/tmp/" only[memory-safe]
            mkdir -p "$airbender_directory"
            acsreport_2_4ghz_tablefile="$airbender_directory/acsreport_2_4ghz";  acsreport_2_4ghz_jsonfile="$airbender_directory/acsreport_2_4ghz.json";  acsreport_temp_2_4ghz="$airbender_directory/temp_2_4ghz.txt";
            temp_file_2_4ghz="$airbender_directory/rmtemp_2_4ghz";
            wid_2_4ghz="$airbender_directory/wid_2_4ghz";  wid_2_4ghz_json="$airbender_directory/wid_2_4ghz.json";
            log_save="/tmp/all_spectrumdata/airbender_2_4GHz.log";
            echo -n "" > "$log_save";  echo -n "###LOGS:-" > "$log_save"
            mkdir -p "/tmp/Rf_spectral_logfiles";
            log_savefor_runstatus="/tmp/Rf_spectral_logfiles/log_airbender_2_4GHz.log";    ###save log for debugging purpose
            ###//////////////////////////////////////////////////
            ###//////////////////////////////////////////////////////////REQUIRED-RADIO-AND-INTERFACE-FETCHING-LOGIC////////////////////////////////////////////////////////////////////////////////
            function universal_interface_fetch__2_4GHz()
            {
                if grep -qE "QN-(I-270.*|I-470.*)" /etc/model; then
                    wifiN_2_4ghz=wifi1;
                else
                    wifiN_2_4ghz=wifi0;
                fi
                iwconfig_temporary="$airbender_directory/iwconfigtemp";
                iwconfig > "$iwconfig_temporary";
                output1=$(grep -A1 -e "ath[01]*" "$iwconfig_temporary" | awk '
                    /ath00|ath[0-9]/ {interface=$1; freq_found=1}
                    /Frequency:/ && freq_found {gsub(/.*Frequency:/, "", $0); split($0, freq, " "); gsub(/\..*/, "", freq[1]); print interface "=" freq[1]; freq_found=0}
                ');
                interface1=$(echo "$output1" | awk -F '=' '/ath01/ {gsub(/[0-9]/, "", $2); print $1; exit} /ath[0-9]/ {gsub(/[0-9]/, "", $2); print $1; exit}');        ### Extracting only alphabetic part before "="
                if echo "$output1" | grep -E '^ath0[0-9]=2$' >/dev/null; then           ### Check if any interface has a value of 2 and assign accordingly
                    interface_2_4ghz="$interface1";
                fi;
                if [ -n "$interface_2_4ghz" ]; then          ### Check if at least one interface is present
                    echo "interface_2_4ghz=$interface_2_4ghz";
                else
                    echo "Error: Unable to find 2.4GHz interface.";
                    exit 1;
                fi;
            }
            universal_interface_fetch__2_4GHz
            get_currentchannelno_2_4ghz=$(iw "$interface_2_4ghz" info | grep "channel" | awk '/channel/ {print $2}');        ###GET CURRENT CHANNEL NUMBER FOR 2.4GHZ BEFORE SCAN
            ###/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            ###//////////////////////////////////////////////LOG-HANDLER-FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////
             function channel_recheck_2_4GHz()  ###THIS FUNCTION CHECK FOR CHANNEL ,IT MAKE CHANNEL TO THAT IT IS BEFORE SCAN FOR 2.4GHZ
             {
                get_afterscanchannelno_2_4ghz=$(iw "$interface_2_4ghz" info | grep "channel" | awk '/channel/ {print $2}')
                max_attempts=10     ###WILL ONLY TRY FOR 10 TIMES MAX,TO AVOID LOOP PROBLEMS[LOOPFAIL-SAFE]
                attempts=0
                echo "#########2_4GHZ#########" | tee -a "$log_savefor_runstatus"
                while [ "$get_afterscanchannelno_2_4ghz" != "$get_currentchannelno_2_4ghz" ] && [ $attempts -lt $max_attempts ]; do
                {
                    echo "=>BEFORE AIRBENDER SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_2_4ghz ~ AFTER AIRBENDER SCAN-CHANNEL: $get_afterscanchannelno_2_4ghz"
                    echo "=>MISMATCH, REDOING/REAPPLYING CHANGES"
                    echo "=>CHANGES COMPLETED"
                } | tee -a "$log_savefor_runstatus"
                    sleep 5
                    timeout -t 1 athssd -i "$wifiN_2_4ghz" -j "$interface_2_4ghz" -s "$get_currentchannelno_2_4ghz"
                    get_afterscanchannelno_2_4ghz=$(iw "$interface_2_4ghz" info | grep "channel" | awk '/channel/ {print $2}')   # Update the after-scan channel for the next iteration
                    ((attempts++))  # Increment attempts
                done
                {
                echo "=>BEFORE AIRBENDER SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_2_4ghz ~ AFTER AIRBENDER SCAN-CHANNEL: $get_afterscanchannelno_2_4ghz"
                echo "=>AP CHANNEL IS SET TO THE CHANNEL IT WAS BEFORE SCANNING FOR 2.4GHZ"
                echo "########################"
                echo "..."
                echo "..."
                echo "..."
                } | tee -a "$log_savefor_runstatus"
            }
            function runstatus_log()
            {
                {
                echo "############################################################################################################################################"
                echo "=>AIRBENDER SCRIPT LAST RUN ON : $formatted_date IN APGUID $mac to generate report on channel loads and interfering aps data."
                echo "############################################################################################################################################"
                } | tee -a "$log_savefor_runstatus"
            }
            ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            # MQTT configuration
            topic="/airbender"
            ####################


            ###############################################################################################################################
            function channelstats_fetcher_2_4GHz() ### THIS GENERATES ADVANCE SPECTRUM CAPABILITES REPORT FOR CHANNEL UTILIZATION
            {
                ### Counter for retry attempts
                tries=0
                max_tries=500
                ### FOR 2.4GHZ CHANNELS
                timeout -t 3 iwpriv wfi1 acs_2g_allch 1;  timeout -t 3 iwpriv wifi1 acs_rank_en 1;
                timeout -t 10 iwconfig "$interface_2_4ghz" channel 0;  timeout -t 10 wifitool "$interface_2_4ghz" acsreport;
                sleep 6
                while true; do
                    output=$(wifitool "$interface_2_4ghz" acsreport | grep -A1000 " The number of channels scanned for acs report is")
                    if echo "$output" | grep "2412("; then
                        echo "$output" > "$acsreport_2_4ghz_tablefile"
                        break
                    else
                        tries=$((tries+1))
                        if [ "$tries" -ge "$max_tries" ]; then
                        {
                        echo "SAFETY~DEBUGGING FEATURE IF AIRBENDER FAILS TO PROVIDE RESULT DUE TO VARIOUS REASONS"
                        echo "Warning:No match after $max_tries tries. athssd/acsreport is not generating Channel utilization,debug manually,or check in for ap driver/firmware or try again after sometimes"
                        echo "TERMINATING..."
                        } | tee -a "$log_save"
                            exit 1
                        fi
                    fi
                done
            }
            function neighbour_ap_fetcher_2_4GHz()  ### THIS GENERATES ADVANCE SPECTRUM CAPABILITES REPORT FOR AP INTERFERENCE DETECTION
            {
                max_tries=100;  ### Counter for retry attempts
                ### FOR 2.4GHZ CHANNELS
                while true; do
                    output=$(grep -A1000 "Additonal Channel" "$acsreport_2_4ghz_tablefile");
                    if echo "$output" | grep "1"; then
                        echo "$output" | tee -a "$wid_2_4ghz";
                        break
                    else
                        tries=$((tries+1))
                        if [ "$tries" -ge "$max_tries" ]; then
                        {
                        echo "SAFETY~DEBUGGING FEATURE IF AIRBENDER FAILS TO PROVIDE RESULT DUE TO VARIOUS REASONS";
                        echo "Warning:No match after $max_tries tries. athssd/acsreport is not generating Additional Channel Statistic as to get channel interference for the ap,debug manually,look in for ap driver/firmware or try again after sometimes";
                        echo "TERMINATING...";
                        } | tee -a "$log_save"
                            break
                        fi
                    fi
                done
            }
            ###############################################################################################################################

        ###############################################################################################################################
        function band_2_4ghz_channelstats_ap_info_makejson()
        {
        #################################################################################################################
        ###For 2_4ghz channel frequency
        #################################################################################################################
        awk '/2412\(/{flag=1; print; next} /ACS_/{flag=0} flag' "$acsreport_2_4ghz_tablefile" > "$acsreport_temp_2_4ghz";
        sort -k2,2n -u "$acsreport_temp_2_4ghz" > "$temp_file_2_4ghz";  mv "$temp_file_2_4ghz" "$acsreport_temp_2_4ghz";

        Channel_Frequency=$(awk -F' ' '{gsub(/\(/, ""); print $1}' $acsreport_temp_2_4ghz);  channel_no=$(awk -F' ' '{gsub(/[()]/, ""); print $2}' $acsreport_temp_2_4ghz);  number_bss=$(awk -F' ' '{gsub(/[()]/, ""); print $3}' $acsreport_temp_2_4ghz);
        MinRssi=$(awk -F' ' '{gsub(/[()]/, ""); print $4}' $acsreport_temp_2_4ghz);  MaxRssi=$(awk -F' ' '{gsub(/[()]/, ""); print $5}' $acsreport_temp_2_4ghz);  noise_floor=$(awk -F' ' '{gsub(/[()]/, ""); print $6}' $acsreport_temp_2_4ghz);
        channel_load=$(awk -F' ' '{gsub(/[()]/, ""); print $7}' $acsreport_temp_2_4ghz);  Spectrum_Load=$(awk -F' ' '{gsub(/[()]/, ""); print $8}' $acsreport_temp_2_4ghz);  Secondary_Channel=$(awk -F' ' '{gsub(/[()]/, ""); print $9}' $acsreport_temp_2_4ghz);
        Rank=$(awk -F' ' '{gsub(/[()]/, ""); print $19}' $acsreport_temp_2_4ghz);

        IFS=$'\n'  ### Set Internal Field Separator to newline to iterate over lines
        channel_stats="["
        delimiter=""
        for i in $(seq "$(echo "$Channel_Frequency" | wc -l)"); do
            json_string=$(printf '{
                "Channel_Frequency": "%s",
                "channel_no": "%s",
                "number_bss": "%s",
                "MinRssi": "%s",
                "MaxRssi": "%s",
                "noise_floor": "%s",
                "channel_load": "%s",
                "Spectrum_Load": "%s",
                "Secondary_Channel": "%s",
                "Rank": "%s"
            }' \
            "$(echo "$Channel_Frequency" | sed -n "${i}p")" \
            "$(echo "$channel_no" | sed -n "${i}p")" \
            "$(echo "$number_bss" | sed -n "${i}p")" \
            "$(echo "$MinRssi" | sed -n "${i}p")" \
            "$(echo "$MaxRssi" | sed -n "${i}p")" \
            "$(echo "$noise_floor" | sed -n "${i}p")" \
            "$(echo "$channel_load" | sed -n "${i}p")" \
            "$(echo "$Spectrum_Load" | sed -n "${i}p")" \
            "$(echo "$Secondary_Channel" | sed -n "${i}p")" \
            "$(echo "$Rank" | sed -n "${i}p")")
            channel_stats="$channel_stats$delimiter$json_string";  delimiter=",\n";
        done
        channel_stats="$channel_stats\n]"
        echo -e "{
        \"time\": \"$formatted_date\",
        \"APGUID\": \"$mac\",
        \"Action\": \"$action_name_2_4ghz_channel_utilization\",
        \"Ifname\": \"$adjusted_interfacename_2_4ghz\",
        \"channel_stats\": $channel_stats
        }" > "$acsreport_2_4ghz_jsonfile"
        }

      function band_2_4ghz_neighbour_ap_info_makejson()
        {
            input_file="$wid_2_4ghz"    ### Assuming the input data is stored in a file named 'input.txt'
            ### Check if the file exists
            if [ ! -f "$input_file" ]; then
            echo "Error: Input file '$input_file' not found."
            exit 1
            fi
            output_file="$wid_2_4ghz_json"    ### Output file for JSON data
            rm -rf "$output_file"       ### Remove existing output file
            bssid_regex='^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'  # Define regular expression for BSSID
            ### Variable to store channel stats
            channel_stats="["
            mac=$(ifconfig br-wan | head -n1 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')
            formatted_date=$(date +"%d-%m-%Y %I:%M:%S %p")
            ### Process each line in the input file
            while IFS= read -r line; do
                ### Extract relevant fields from the line using awk
                index=$(echo "$line" | awk '{print $1}')
                channel=$(echo "$line" | awk '{print $2}')
                nbss=$(echo "$line" | awk '{print $3}')
                ssid=$(echo "$line" | awk '{print $4}')
                bssid=$(echo "$line" | awk '{print $5}')
                rssi=$(echo "$line" | awk '{print $6}')
                rssi=$(( $(echo "$rssi" | awk '{print $1 - 95}') ))
                phymode=$(echo "$line" | awk '{print $7}')
                ### Check if all required fields are present and BSSID matches the regex
                if [ -n "$index" ] && [ -n "$channel" ] && [ -n "$nbss" ] && [ -n "$ssid" ] && [ -n "$rssi" ] && [ -n "$phymode" ] && echo "$bssid" | grep -E -q "$bssid_regex"; then
                    ### Create JSON string directly using printf
                    json=$(printf '{
                        "Index": "%s",
                        "channel": "%s",
                        "Nbss": "%s",
                        "ssid": "%s",
                        "bssid": "%s",
                        "rssi": "%s",
                        "phymode": "%s"
                    }' "$index" "$channel" "$nbss" "$ssid" "$bssid" "$rssi" "$phymode")
                    ### Append JSON string to channel_stats with a comma and new line
                    channel_stats="$channel_stats\n$json,"
                else
                    echo "Skipping line with missing or invalid fields: $line" >&2
                fi
            done <"$input_file"
            channel_stats="${channel_stats%,}"      ### Remove the trailing comma from the last line in channel_stats
            channel_stats="$channel_stats\n]"       ### Close the channel_stats array
            ### Final JSON output
            echo -e "{
            \"time\": \"$formatted_date\",
            \"APGUID\": \"$mac\",
            \"Action\": \"$action_name_2_4_ghz_wid\",
            \"Ifname\": \"$adjusted_interfacename_2_4ghz\",
            \"neighbors\": $channel_stats
            }" > "$output_file"
        }
    ###//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ###################################################################################################################################################
    ### THIS FUNCTION SEND DATA TO CLOUD VIA MQTT BY READING FROM SPECIFIED FILES
    ###################################################################################################################################################
    function send_data_via_mqtt_2_4GHz()
    {
            json_file_2_4ghz_cu="$acsreport_2_4ghz_jsonfile"; json_file_2_4ghz_wid="$wid_2_4ghz_json";
            if [ ! -f "$json_file_2_4ghz_cu" ] || [ ! -f "$json_file_2_4ghz_wid" ];      ### Check if the JSON file exists
            then
                exit 1
            fi
            json_data_2_4ghz_cu=$(cat "$json_file_2_4ghz_cu");  json_file_2_4ghz_wid=$(cat "$json_file_2_4ghz_wid");
            timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_data_2_4ghz_cu" -r       ### Send data to MQTT topic
            timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_file_2_4ghz_wid" -r
    }
    ###################################################################################################################################################
    ###################################################################################################################################################
        function model_check_2_4GHz()
        {
            ###MAIN IF LOGIC CONDITION TO CALL FUNCTION AS PER MODEL   <<<<========== MAIN BODY RESPONSIBLE FOR ACTUAL CALLING OF REQUIRED FUNTION BASED ON AP MODELS
            if grep -qE "QN-(H-245.*|O-230.*|I-220.*|O-240.*|H-250.*|I-270.*|I-280.*|I-290.*|O-290.*|I-470.*|I-480.*|O-480.*|I-490.*|O-490.*)" /etc/model;      ### Check if the grep result matches the desired patterns
            then
                mkdir -p "$airbender_directory";  echo -n "" > "$acsreport_2_4ghz_tablefile";  echo -n "" > "$acsreport_2_4ghz_jsonfile";
                echo -n "" > "$acsreport_temp_2_4ghz";  echo -n "" > "$wid_2_4ghz";  echo -n "" > "$wid_2_4ghz_json";
                channelstats_fetcher_2_4GHz
                neighbour_ap_fetcher_2_4GHz
                band_2_4ghz_channelstats_ap_info_makejson
                band_2_4ghz_neighbour_ap_info_makejson
                send_data_via_mqtt_2_4GHz
                rm -rf "$acsreport_2_4ghz_tablefile"  "$acsreport_2_4ghz_jsonfile"  "$acsreport_temp_2_4ghz"  "$temp_file_2_4ghz"
                rm -rf "$wid_2_4ghz"  "$wid_2_4ghz_json"
                ###rm -rf $airbender_directory
                echo "EVERY PROCESS EXECUTED SUCCESSFULLY WITHOUT ANY ISSUES,ON LAST RECORED TIME ON : $formatted_date" | tee -a  "$log_save"
            else
                echo "Model does not match the specified conditions."
            fi
        }
        #### THIS FUCNTION CHECKS IF SCRIPT IS PROVIDED WITH ARGUMENT OF 1/0 TO MAKE IT IN STATE OF ENABLE/DISABLE
        function initialize_SCBHC752K()
        {
            if [ -n "$1" ]; then    ### If argument is provided, execute code based on the argument
                if [ "$1" == "Neighbors" ] || [ "$1" == "ChanInfo" ]; then
                    echo "Running the script with argument '1' or 'Neighbors' or 'ChanInfo'..."
                    model_check_2_4GHz
                    echo "" > "$log_savefor_runstatus"
                    channel_recheck_2_4GHz
                    runstatus_log
                    else
                    echo "Exiting the script with argument '0'..."
                    exit 0
                fi
                else
                echo "No Argument Provided,Exiting"
                exit 0
            fi
        }
        initialize_SCBHC752K "$1"
        ###################################################################################################################################################
    echo "Running airbender_2_4GHz.sh"
    rm -f "$LOCK_FILE"      # Release the lock
    trap - INT TERM EXIT
else
    echo "Script is already running, exiting."
    exit 1
fi
#######################################################################################################################
###///END_OF_FILE
EOF
)
echo "$script_content_2_4ghz" > "/tmp/all_spectrumdata/airbender_2_4ghz"
}

################################################################///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
################################################################///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function band_5ghz_thread()
{
script_content_5ghz=$(cat <<'EOF'
###///START_OF_FILE
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
###LOCKING SCRIPT TO PREVENT REDUNDANT/DUPLICATE PROCESSES FROM EXECUTING IN THE BACKGROUND,HELPFUL IN AVOIDING MULTIPLE INSTANCES OF THE SAME SCRIPT RUNNING
###SIMULTANEOUSLY IF REQUESTED,MULTIPLE TIMES BY THE USER IN THE CLOUD, WHETHER INTENTIONALLY OR ACCIDENTALLY.
LOCK_FILE="/var/run/airbender_5GHz.lock"       ###LOCK INITIATING
if ( set -o noclobber; echo "$$" > "$LOCK_FILE") 2> /dev/null;  ###LOCK CONDITION CHECK
then
    trap 'rm -f "$LOCK_FILE"; exit $?' INT TERM EXIT
            ###//////////////////////////////////////////////
            ###GLOBAL VARIABLES,FUNCTIONS AND FILES LOCATION
            ###//////////////////////////////////////////////
            mac=$(ifconfig br-wan | head -n1 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}');  formatted_date=$(date +"%d-%m-%Y %I:%M:%S %p");
            action_name_5ghz_channel_utilization="ChanInfoOnDemand";  action_name_5_ghz_wid="NeighborsOnDemand";
            adjusted_interfacename_5ghz="wifi1";         ###to make ath10 named as wifi0 for cloud understanding for 5ghz
            airbender_directory="/tmp/all_spectrumdata/airbender_data";      ###all data will be processed and stored in "/tmp/" only[memory-safe]
            mkdir -p "$airbender_directory";
            acsreport_5ghz_tablefile="$airbender_directory/acsreport_5ghz";  acsreport_5ghz_jsonfile="$airbender_directory/acsreport_5ghz.json";  acsreport_temp_5ghz="$airbender_directory/temp_5ghz.txt";
            temp_file_5ghz="$airbender_directory/rmtemp_5ghz";
            wid_5ghz="$airbender_directory/wid_5_ghz";  wid_5ghz_json="$airbender_directory/wid_5ghz.json";
            log_save="/tmp/all_spectrumdata/airbender_5GHz.log";
            echo -n "" > "$log_save";  echo -n "###LOGS:-" > "$log_save";
            mkdir -p "/tmp/Rf_spectral_logfiles";
            log_savefor_runstatus="/tmp/Rf_spectral_logfiles/log_airbender_5GHz.log";    ###save log for debugging purpose
            ###//////////////////////////////////////////////////
            ###//////////////////////////////////////////////////////////REQUIRED-RADIO-AND-INTERFACE-FETCHING-LOGIC////////////////////////////////////////////////////////////////////////////////
            function universal_interface_fetch_5ghz()
            {
                if grep -qE "QN-(I-270.*|I-470.*)" /etc/model; then      ###if,interface_2_4ghz is not equal to ath0* and interface_5ghz is not equal to ath1* than reverse assign value.
                    wifiN_5ghz=wifi0;       ###FOR I270 AND I470
                else
                    wifiN_5ghz=wifi1;    ###FOR OTHERS:
                fi;
                iwconfig_temporary="$airbender_directory/iwconfigtemp";
                iwconfig > "$iwconfig_temporary";
                output2=$(grep -A1 -e "ath[01]*" $iwconfig_temporary | awk '
                    /ath10|ath[1-9]/ {interface=$1; freq_found=1}
                    /Frequency:/ && freq_found {gsub(/.*Frequency:/, "", $0); split($0, freq, " "); gsub(/\..*/, "", freq[1]); print interface "=" freq[1]; freq_found=0}
                ');
                interface2=$(echo "$output2" | awk -F '=' '/ath11/ {gsub(/[0-9]/, "", $2); print $1; exit} /ath[0-9]/ {gsub(/[0-9]/, "", $2); print $1; exit}');    ### Extracting only alphabetic part before "="
                if echo "$output2" | grep -E '^ath1[0-9]=5$' >/dev/null; then       ### Check if any interface has a value of 5 and assign accordingly
                    interface_5ghz="$interface2";
                fi;
                if [ -n "$interface_5ghz" ]; then       ### Check if the 5GHz interface is present
                    echo "interface_5ghz=$interface_5ghz";      ### The 5GHz interface is present
                else
                    echo "Error: Unable to find 5GHz interface.";   ### No 5GHz interface found
                    exit 1;
                fi;
                echo "interface_5ghz=$interface_5ghz";      ### Print the assigned value
            }
            universal_interface_fetch_5ghz
            get_currentchannelno_5ghz=$(iw "$interface_5ghz" info | grep "channel" | awk '/channel/ {print $2}');       ###GET CURRENT CHANNEL NUMBER FOR 5GHZ BEFORE SCAN
            ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            ###//////////////////////////////////////////////LOG-HANDLER-FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////
            function channel_recheck_5ghz()     ###THIS FUNCTION CHECK FOR CHANNEL ,IT MAKE CHANNEL TO THAT IT IS BEFORE SCAN FOR 5GHZ
            {
                get_afterscanchannelno_5ghz=$(iw "$interface_5ghz" info | grep "channel" | awk '/channel/ {print $2}')
                max_attempts=10     ###WILL ONLY TRY FOR 10 TIMES MAX,TO AVOID LOOP PROBLEMS[LOOPFAIL-SAFE]
                attempts=0
                    echo "##########5GHZ##########" | tee -a "$log_savefor_runstatus"
                while [ "$get_afterscanchannelno_5ghz" != "$get_currentchannelno_5ghz" ] && [ "$attempts" -lt "$max_attempts" ]; do
                {
                    echo "=>BEFORE AIRBENDER SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_5ghz ~ AFTER AIRBENDER SCAN-CHANNEL: $get_afterscanchannelno_5ghz"
                    echo "=>MISMATCH, REDOING/REAPPLYING CHANGES"
                    echo "=>CHANGES COMPLETED" | tee -a "$log_savefor_runstatus"
                } | tee -a "$log_savefor_runstatus"
                    sleep 5
                    timeout -t 1 athssd -i "$wifiN_5ghz" -j "$interface_5ghz" -s "$get_currentchannelno_5ghz"
                    # Update the after-scan channel for the next iteration
                    get_afterscanchannelno_5ghz=$(iw "$interface_5ghz" info | grep "channel" | awk '/channel/ {print $2}')
                    ((attempts++))
                done
                {
                echo "=>BEFORE AIRBENDER SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_5ghz ~ AFTER AIRBENDER SCAN-CHANNEL: $get_afterscanchannelno_5ghz"
                echo "=>AP CHANNEL IS SET TO THE CHANNEL IT WAS BEFORE SCANNING FOR 5GHZ"
                echo "########################"
                echo "..."
                echo "..."
                echo "..."
                } | tee -a "$log_savefor_runstatus"
            }

            function runstatus_log()
            {
                {
                echo "############################################################################################################################################"
                echo "=>AIRBENDER SCRIPT LAST RUN ON : $formatted_date IN APGUID $mac to generate report on channel loads and interfering aps data."
                echo "############################################################################################################################################"
                } | tee -a "$log_savefor_runstatus"
            }
            ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            topic="/airbender"      # MQTT configuration
            ##########################################


        ###############################################################################################################################
            function channelstats_fetcher_5GHz() ### THIS GENERATES ADVANCE SPECTRUM CAPABILITES REPORT FOR CHANNEL UTILIZATION
            {
                tries=0
                ### FOR 5GHZ CHANNELS
                timeout -t 3 iwpriv wifi0 acs_2g_allch 1;  timeout -t 3 iwpriv wifi0 acs_rank_en 1;
                timeout -t 10 iwconfig "$interface_5ghz" channel 0;  timeout -t 10 wifitool "$interface_5ghz" acsreport;
                sleep 11
                while true; do
                    output=$(wifitool "$interface_5ghz" acsreport | grep -A1000 " The number of channels scanned for acs report is")
                    if echo "$output" | grep "5180("; then
                        echo "$output" > "$acsreport_5ghz_tablefile"
                        break
                    else
                        tries=$((tries+1))
                        if [ "$tries" -ge "$max_tries" ]; then
                        {
                        echo "SAFETY~DEBUGGING FEATURE IF AIRBENDER FAILS TO PROVIDE RESULT DUE TO VARIOUS REASONS"
                        echo "Warning:No match after $max_tries tries. athssd/acsreport is not generating Channel utilization,debug manually,or check in for ap driver/firmware or try again after sometimes"
                        echo "TERMINATING..."
                        } | tee -a "$log_save"
                            exit 1
                        fi
                    fi
                done
            }

            function neighbour_ap_fetcher_5GHz()    ### THIS GENERATES ADVANCE SPECTRUM CAPABILITES REPORT FOR AP INTERFERENCE DETECTION
            {
                tries=0
                ### FOR 5GHZ CHANNELS
                while true; do
                    output=$(grep -A1000 "Additonal Channel" "$acsreport_5ghz_tablefile")
                    if echo "$output" | grep "1"; then
                        echo "$output" | tee -a "$wid_5ghz"
                        break
                    else
                        tries=$((tries+1))
                        if [ "$tries" -ge "$max_tries" ]; then
                        {
                        echo "SAFETY~DEBUGGING FEATURE IF AIRBENDER FAILS TO PROVIDE RESULT DUE TO VARIOUS REASONS"
                        echo "Warning:No match after $max_tries tries. athssd/acsreport is not generating Additional Channel Statistic as to get channel interference for the ap,debug manually,look in for ap driver/firmware or try again after sometimes"
                        echo "TERMINATING..."
                        } | tee -a "$log_save"
                            break
                        fi
                    fi
                done
            }
        ###############################################################################################################################

        ###############################################################################################################################
        function band_5ghz_channelstats_ap_info_makejson()
        {
            #################################################################################################################
            ###For 5ghz channel frequency
            #################################################################################################################
            awk '/5180\(/{flag=1; print; next} /ACS_/{flag=0} flag' "$acsreport_5ghz_tablefile" > "$acsreport_temp_5ghz";
            sort -k2,2n -u "$acsreport_temp_5ghz" > "$temp_file_5ghz";  mv "$temp_file_5ghz" "$acsreport_temp_5ghz";

            Channel_Frequency=$(awk '{gsub(/\([^(]*\)/, ""); print $1}' $acsreport_temp_5ghz);  channel_no=$(awk -F'[()]' '{print $2}' $acsreport_temp_5ghz);  number_bss=$(awk '{gsub(/\([^(]*\)/, ""); print $2}' $acsreport_temp_5ghz);
            MinRssi=$(awk '{gsub(/\([^(]*\)/, ""); print $3}' $acsreport_temp_5ghz);  MaxRssi=$(awk '{gsub(/\([^(]*\)/, ""); print $4}' $acsreport_temp_5ghz);  noise_floor=$(awk '{gsub(/\([^(]*\)/, ""); print $5}' $acsreport_temp_5ghz);
            channel_load=$(awk '{gsub(/\([^(]*\)/, ""); print $6}' $acsreport_temp_5ghz);  Spectrum_Load=$(awk '{gsub(/\([^(]*\)/, ""); print $7}' $acsreport_temp_5ghz);  Secondary_Channel=$(awk '{gsub(/\([^(]*\)/, ""); print $8}' $acsreport_temp_5ghz);
            Rank=$(awk '{gsub(/\([^(]*\)/, ""); print $18}' $acsreport_temp_5ghz);

            IFS=$'\n'  ### Set Internal Field Separator to newline to iterate over lines
            channel_stats="["
            delimiter=""
                for i in $(seq "$(echo "$Channel_Frequency" | wc -l)"); do
                    json_string=$(printf '{
                        "Channel_Frequency": "%s",
                        "channel_no": "%s",
                        "number_bss": "%s",
                        "MinRssi": "%s",
                        "MaxRssi": "%s",
                        "noise_floor": "%s",
                        "channel_load": "%s",
                        "Spectrum_Load": "%s",
                        "Secondary_Channel": "%s",
                        "Rank": "%s"
                    }' \
                    "$(echo "$Channel_Frequency" | sed -n "${i}p")" \
                    "$(echo "$channel_no" | sed -n "${i}p")" \
                    "$(echo "$number_bss" | sed -n "${i}p")" \
                    "$(echo "$MinRssi" | sed -n "${i}p")" \
                    "$(echo "$MaxRssi" | sed -n "${i}p")" \
                    "$(echo "$noise_floor" | sed -n "${i}p")" \
                    "$(echo "$channel_load" | sed -n "${i}p")" \
                    "$(echo "$Spectrum_Load" | sed -n "${i}p")" \
                    "$(echo "$Secondary_Channel" | sed -n "${i}p")" \
                    "$(echo "$Rank" | sed -n "${i}p")")
                    channel_stats="$channel_stats$delimiter$json_string";  delimiter=",\n";
                done
                channel_stats="$channel_stats\n]"
                echo -e "{
                \"time\": \"$formatted_date\",
                \"APGUID\": \"$mac\",
                \"Action\": \"$action_name_5ghz_channel_utilization\",
                \"Ifname\": \"$adjusted_interfacename_5ghz\",
                \"channel_stats\": $channel_stats
                }" > "$acsreport_5ghz_jsonfile"
            ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        }

     function band_5ghz_neighbour_ap_info_makejson()
            {
                input_file="$wid_5ghz";          ### Assuming the input data is stored in a file named 'input.txt'
                if [ ! -f "$input_file" ]; then         ### Check if the file exists
                echo "Error: Input file '$input_file' not found.";
                exit 1
                fi
                output_file="$wid_5ghz_json";            ### Output file for JSON data
                rm -rf "$output_file";           ### Remove existing output file
                bssid_regex='^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$';          ### Define regular expression for BSSID
                channel_stats="[";         ### Variable to store channel stats
                mac=$(ifconfig br-wan | head -n1 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}');  formatted_date=$(date +"%d-%m-%Y %I:%M:%S %p");
                channel_stats="[";           ### Variable to store channel stats
                delimiter="";
                while IFS= read -r line; do     ### Process each line in the input file
                    index=$(echo "$line" | awk '{print $1}');  channel=$(echo "$line" | awk '{print $2}');  nbss=$(echo "$line" | awk '{print $3}');  ssid=$(echo "$line" | awk '{print $4}');      ### Extract relevant fields from the line using awk
                    bssid=$(echo "$line" | awk '{print $5}');  rssi=$(echo "$line" | awk '{print $6}'); rssi=$(( $(echo "$rssi" | awk '{print $1 - 95}') )); phymode=$(echo "$line" | awk '{print $7}');
                    if [ -n "$index" ] && [ -n "$channel" ] && [ -n "$nbss" ] && [ -n "$ssid" ] && [ -n "$rssi" ] && [ -n "$phymode" ] && echo "$bssid" | grep -E -q "$bssid_regex"; then       ### Check if all required fields are present and BSSID matches the regex
                        ### Create JSON string directly using printf
                        json=$(printf '{
                            "Index": "%s",
                            "channel": "%s",
                            "Nbss": "%s",
                            "ssid": "%s",
                            "bssid": "%s",
                            "rssi": "%s",
                            "phymode": "%s"
                        }' "$index" "$channel" "$nbss" "$ssid" "$bssid" "$rssi" "$phymode")
                        channel_stats="$channel_stats$delimiter$json";  delimiter=",\n";        ### Append JSON string to channel_stats with a comma and new line
                    else
                        echo "Skipping line with missing or invalid fields: $line" >&2
                    fi
                done < "$input_file"
                channel_stats="${channel_stats%,}";  ### Remove the trailing comma from the last line in channel_stats
                channel_stats="$channel_stats\n]";    ### Close the channel_stats array
                ### Final JSON output
                echo -e "{
                \"time\": \"$formatted_date\",
                \"APGUID\": \"$mac\",
                \"Action\": \"$action_name_5_ghz_wid\",
                \"Ifname\": \"$adjusted_interfacename_5ghz\",
                \"neighbors\": $channel_stats
                }" > "$output_file"
            }
        ###//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


    ###################################################################################################################################################
    ### THIS FUNCTION SEND DATA TO CLOUD VIA MQTT BY READING FROM SPECIFIED FILES
    ###################################################################################################################################################
    function send_data_via_mqtt_5GHz()
    {
            json_file_5ghz_cu="$acsreport_5ghz_jsonfile";  json_file_5ghz_wid="$wid_5ghz_json";
            if [ ! -f "$json_file_5ghz_cu" ] || [ ! -f "$json_file_5ghz_wid" ];     ### Check if the JSON file exists
            then
                exit 1
            fi
            json_data_5ghz_cu=$(cat "$json_file_5ghz_cu");  json_file_5ghz_wid=$(cat "$json_file_5ghz_wid");
            timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_data_5ghz_cu"  -r        ### Send data to MQTT topic
            timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_file_5ghz_wid" -r
    }
    ###################################################################################################################################################
    ###################################################################################################################################################
        function model_check_5GHz()
        {
            ###MAIN IF LOGIC CONDITION TO CALL FUNCTION AS PER MODEL   <<<<========== MAIN BODY RESPONSIBLE FOR ACTUAL CALLING OF REQUIRED FUNTION BASED ON AP MODELS
            if grep -qE "QN-(H-245.*|O-230.*|I-220.*|O-240.*|H-250.*|I-270.*|I-280.*|I-290.*|O-290.*|I-470.*|I-480.*|O-480.*|I-490.*|O-490.*)" /etc/model;      ### Check if the grep result matches the desired patterns
            then
                mkdir -p "$airbender_directory";  echo -n "" > "$acsreport_5ghz_tablefile";  echo -n "" > "$acsreport_5ghz_jsonfile";  echo -n "" > "$acsreport_temp_5ghz";  echo -n "" > "$wid_5ghz";  echo -n "" > "$wid_5ghz_json";
                channelstats_fetcher_5GHz
                neighbour_ap_fetcher_5GHz
                band_5ghz_channelstats_ap_info_makejson
                band_5ghz_neighbour_ap_info_makejson
                send_data_via_mqtt_5GHz
                rm -rf "$acsreport_5ghz_tablefile" "$acsreport_5ghz_jsonfile" "$acsreport_temp_5ghz" "$temp_file_5ghz" "$wid_5ghz" "$wid_5ghz_json"
                ###rm -rf $airbender_directory
                echo "EVERY PROCESS EXECUTED SUCCESSFULLY WITHOUT ANY ISSUES,ON LAST RECORED TIME ON : $formatted_date" | tee -a  "$log_save"
            else
                echo "Model does not match the specified conditions."
            fi
        }

        #### THIS FUCNTION CHECKS IF SCRIPT IS PROVIDED WITH ARGUMENT OF 1/0 TO MAKE IT IN STATE OF ENABLE/DISABLE
        function initialize_SCBHC752K()
        {
            if [ -n "$1" ]; then    ### If argument is provided, execute code based on the argument
                if [ "$1" == "Neighbors" ] || [ "$1" == "ChanInfo" ]; then
                    echo "Running the script with argument '1' or 'Neighbors' or 'ChanInfo'..."
                    model_check_5GHz
                    echo "" > "$log_savefor_runstatus"
                    channel_recheck_5ghz
                    runstatus_log
                    else
                    echo "Exiting the script with argument '0'..."
                    exit 0
                fi
                else
                echo "No Argument Provided,Exiting"
                exit 0
            fi
        }
        initialize_SCBHC752K "$1"
     ###################################################################################################################################################
    echo "Running airbender_5GHz.sh"
    rm -f "$LOCK_FILE"      # Release the lock
    trap - INT TERM EXIT
else
    echo "Script is already running, exiting."
    exit 1
fi
#######################################################################################################################
###///END_OF_FILE
EOF
)
echo "$script_content_5ghz" > "/tmp/all_spectrumdata/airbender_5ghz"
}

function thread_manager_for_2_4ghz_and_5ghz_bands()
 {
    if [ "$1" == "Neighbors" ] || [ "$1" == "ChanInfo" ]; then
        command="$1"
        band_2_4ghz_thread
        band_5ghz_thread
        sleep 1
        sh "/tmp/all_spectrumdata/airbender_2_4ghz" "$command" && rm "/tmp/all_spectrumdata/airbender_2_4ghz" &
        sleep 1
        sh "/tmp/all_spectrumdata/airbender_5ghz" "$command" && rm "/tmp/all_spectrumdata/airbender_5ghz" &
        sleep 1
    else
        echo "Invalid input"
        exit 1
    fi
}
thread_manager_for_2_4ghz_and_5ghz_bands "$1"
