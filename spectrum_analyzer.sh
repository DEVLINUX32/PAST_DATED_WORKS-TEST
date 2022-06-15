#!/bin/bash
###|====================================================================================================================================================================================================
###|SCRIPT_PATH                          :  /usr/lib/lua/luci/ap/spectrum_analyzer.sh
###|USAGE                                :  Generate Required Data to plot Spectrum Analyzer Graph
###|OTHER_FILES_CREATION_AND_DEPENDENCY  :  acsreport_2_4ghz,acsreport_2_4ghz.json,acsreport_5ghz,acsreport_5ghz.json
###|ALGORITHM-WORKFLOW                   :  1) Generate AcsReports for both 2.4Ghz and 5ghz that contains information like min/max rssi, bss, noise floor,etc
###|"________________"                   :  2) Use athssd to find rssi interference per channel for both 2.4ghz and 5ghz and also detect microwave,fhss,cw ~wave using athssd
###|"________________"                   :  3) Then store all this collected datas in a file in json string format and then send this to cloud via mqtt.
###|SUPPORT                              :  Only work/tested for qsdk model aps ~[H-245.*|O-230.*|I-240.*|O-240.*|H-250.*|I-270.*|I-280.*|I-290.*|O-290.*|I-470.*|I-480.*|O-480.*|I-490.*|O-490.*]
###|ARGUMENTS                            :  sh /usr/lib/lua/luci/ap/spectrum_analyzer.sh "1/0" "time_in_minutes" || Example: sh /usr/lib/lua/luci/ap/spectrum_analyzer.sh "1" "5"
###|=====================================================================================================================================================================================================
#########################################################################################################################################################################################################

###///START_OF_FILE
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
###GLOBAL VARIABLES AND FILES LOCATION
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
main_directory="/tmp/all_spectrumdata/spectrum_analyzer";
mkdir -p $main_directory;
mkdir -p "/tmp/Rf_spectral_logfiles";
###CHECK-FOR-REQUIRED-PACKAGES
if [ ! -x "/usr/bin/tee" ] || [ ! -x "/usr/bin/timeout" ]; then
    if [ ! -x "/usr/bin/tee" ]; then
        echo "tee is not installed in /usr/bin." ;
    fi
    if [ ! -x "/usr/bin/timeout" ]; then
        echo "timeout is not installed in /usr/bin." ;
    fi
    exit 0;
fi
function universal_interface_fetch_for_both_2_4GHz_and_5GHz()    ###THIS FUNCTION WILL FETCH INTERFACE NAME FOR 2.4GHZ AND 5GHZ BAND FROM AP AUTOMATICALLY,SUPPORT FOR VARIOUS MODELS DESCRIBED ABOVE #TESTED#
{
    if grep -qE "QN-(I-270.*|I-470.*|I-220.*)" /etc/model;
        then
            wifiN_2_4ghz=wifi1; wifiN_5ghz=wifi0;
        else
            wifiN_2_4ghz=wifi0; wifiN_5ghz=wifi1;
    fi
    iwconfig_temporary="$main_directory/iwconfigtemp"
    iwconfig > "$iwconfig_temporary"
    output1=$(grep -A1 -e "ath[01]*" $iwconfig_temporary | awk '
        /ath00|ath[0-9]/ {interface=$1; freq_found=1}
        /Frequency:/ && freq_found {gsub(/.*Frequency:/, "", $0); split($0, freq, " "); gsub(/\..*/, "", freq[1]); print interface "=" freq[1]; freq_found=0}
    ')
    output2=$(grep -A1 -e "ath[01]*" $iwconfig_temporary | awk '
        /ath10|ath[1-9]/ {interface=$1; freq_found=1}
        /Frequency:/ && freq_found {gsub(/.*Frequency:/, "", $0); split($0, freq, " "); gsub(/\..*/, "", freq[1]); print interface "=" freq[1]; freq_found=0}
    ')
    interface1=$(echo "$output1" | awk -F '=' '/ath01/ {gsub(/[0-9]/, "", $2); print $1; exit} /ath[0-9]/ {gsub(/[0-9]/, "", $2); print $1; exit}')
    interface2=$(echo "$output2" | awk -F '=' '/ath11/ {gsub(/[0-9]/, "", $2); print $1; exit} /ath[0-9]/ {gsub(/[0-9]/, "", $2); print $1; exit}')
    if echo "$output1" | grep -E '^ath0[0-9]=2$' >/dev/null; then   ### Check if any interface has a value of 2 or 5 and assign accordingly
        interface_2_4ghz="$interface1";
    fi
    if echo "$output2" | grep -E '^ath1[0-9]=5$' >/dev/null; then
        interface_5ghz="$interface2";
    fi
    if [ -n "$interface_2_4ghz" ] || [ -n "$interface_5ghz" ]; then     ### Check if at least one interface is present
        echo "interface_2_4ghz=$interface_2_4ghz";echo "interface_5ghz=$interface_5ghz";
    else
        echo "Error: Unable to find 2.4GHz or 5GHz interface."  ### No interface found
        exit 1
    fi
}
universal_interface_fetch_for_both_2_4GHz_and_5GHz
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function band_2_4GHz_and_5GHz_thread()
{
#script_content_radio_frequencies=$(cat <<'EOF'
###///START_OF_FILE
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
###LOCKING SCRIPT TO PREVENT REDUNDANT/DUPLICATE PROCESSES FROM EXECUTING IN THE BACKGROUND,HELPFUL IN AVOIDING MULTIPLE INSTANCES OF THE SAME SCRIPT RUNNING
###SIMULTANEOUSLY IF REQUESTED.MULTIPLE TIMES BY THE USER IN THE CLOUD, WHETHER INTENTIONALLY OR ACCIDENTALLY.
LOCK_FILE="/var/run/spectrum_analyzer.lock"       ###LOCK INITIATING
if ( set -o noclobber; echo "$$" > "$LOCK_FILE") 2> /dev/null;  ###LOCK CONDITION CHECK
then
    trap 'rm -f "$LOCK_FILE"; exit $?' INT TERM EXIT
    ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ###GLOBAL VARIABLES AND FILES LOCATION
    ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    mac=$(ifconfig br-wan | head -n1 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')
    adjusted_interfacename_2_4ghz="wifi0"       ###to make ath00 named as wifi0 for cloud understanding for 2.4ghz
    adjusted_interfacename_5ghz="wifi1"         ###to make ath10 named as wifi0 for cloud understanding for 5ghz
    main_directory="/tmp/all_spectrumdata/spectrum_analyzer"
    mkdir -p $main_directory
    filename_2_4ghz="$main_directory/spectral_data_2_4ghz.json"; filename_5ghz="$main_directory/spectral_data_5ghz.json";
    acsreport_2_4ghz_tablefile="$main_directory/acsreport_2_4ghz"; acsreport_5ghz_tablefile="$main_directory/acsreport_5ghz";
    acsreport_temp_2_4ghz="$main_directory/temp_2_4ghz.txt"; acsreport_temp_5ghz="$main_directory/temp_5ghz.txt";
    temp_file_2_4ghz="$main_directory/rmtemp_2_4ghz"; temp_file_5ghz="$main_directory/rmtemp_5ghz";
    spectral_state="$main_directory/spectral_state"
    script_name="/usr/lib/lua/luci/ap/spectrum_analyzer.sh"
    log_save="/tmp/all_spectrumdata/spectrum_analyzer.log"
    echo -n "" > "$log_save";  echo -n "###LOGS:-" > "$log_save";
    mkdir -p "/tmp/Rf_spectral_logfiles"
    log_savefor_runstatus="/tmp/Rf_spectral_logfiles/log_spectrum_analyzer.log"    ###save log for debugging purpose
    external_stopkill_defaultchannel_2_4ghz_datastore="$main_directory/defaultchannel_2_4GHz"
    external_stopkill_defaultchannel_5ghz_datastore="$main_directory/defaultchannel_5GHz"
    ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function universal_interface_fetch()    ###THIS FUNCTION WILL FETCH INTERFACE NAME FOR 2.4GHZ AND 5GHZ BAND FROM AP AUTOMATICALLY,SUPPORT FOR VARIOUS MODELS DESCRIBED ABOVE #TESTED#
    {
        if grep -qE "QN-(I-270.*|I-470.*|I-220.*)" /etc/model;
        then
            wifiN_2_4ghz=wifi1;wifiN_5ghz=wifi0;    ###FOR I270 AND I470
        else
            wifiN_2_4ghz=wifi0;wifiN_5ghz=wifi1;    ###FOR OTHERS:
        fi
        iwconfig_temporary="$main_directory/iwconfigtemp"
        iwconfig > "$iwconfig_temporary"
        output1=$(grep -A1 -e "ath[01]*" $iwconfig_temporary | awk '
            /ath00|ath[0-9]/ {interface=$1; freq_found=1}
            /Frequency:/ && freq_found {gsub(/.*Frequency:/, "", $0); split($0, freq, " "); gsub(/\..*/, "", freq[1]); print interface "=" freq[1]; freq_found=0}
        ')
        output2=$(grep -A1 -e "ath[01]*" $iwconfig_temporary | awk '
            /ath10|ath[1-9]/ {interface=$1; freq_found=1}
            /Frequency:/ && freq_found {gsub(/.*Frequency:/, "", $0); split($0, freq, " "); gsub(/\..*/, "", freq[1]); print interface "=" freq[1]; freq_found=0}
        ')
        interface1=$(echo "$output1" | awk -F '=' '/ath01/ {gsub(/[0-9]/, "", $2); print $1; exit} /ath[0-9]/ {gsub(/[0-9]/, "", $2); print $1; exit}')         ### Extracting only alphabetic part before "="
        interface2=$(echo "$output2" | awk -F '=' '/ath11/ {gsub(/[0-9]/, "", $2); print $1; exit} /ath[0-9]/ {gsub(/[0-9]/, "", $2); print $1; exit}')
        echo "Output 1: $output1"
        echo "Output 2: $output2"
        if echo "$output1" | grep -E '^ath0[0-9]=2$' >/dev/null; then
            interface_2_4ghz="$interface1"
        fi
        if echo "$output2" | grep -E '^ath1[0-9]=5$' >/dev/null; then
            interface_5ghz="$interface2"
        fi
        if [ -n "$interface_2_4ghz" ] || [ -n "$interface_5ghz" ]; then        ### Check if at least one interface is present
            echo "interface_2_4ghz=$interface_2_4ghz"       ### At least one interface is present
            echo "interface_5ghz=$interface_5ghz"
        else
            echo "Error: Unable to find 2.4GHz or 5GHz interface."      ### No interface found
            exit 1
        fi
    }
    universal_interface_fetch
    get_currentchannelno_2_4ghz=$(iw "$interface_2_4ghz" info | grep "channel" | awk '/channel/ {print $2}')   ###GET CURRENT CHANNEL NUMBER FOR 2.4GHZ BEFORE SCAN
    get_currentchannelno_5ghz=$(iw "$interface_5ghz" info | grep "channel" | awk '/channel/ {print $2}')       ###GET CURRENT CHANNEL NUMBER FOR 5GHZ BEFORE SCAN
    echo "$get_currentchannelno_2_4ghz" > "$external_stopkill_defaultchannel_2_4ghz_datastore"
    echo "$get_currentchannelno_5ghz" > "$external_stopkill_defaultchannel_5ghz_datastore"
    ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ###//////////////////////////////////////////////LOG-HANDLER-FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////
    function channel_recheck_2_4ghz()  ###THIS FUNCTION CHECK FOR CHANNEL ,IT MAKE CHANNEL TO THAT IT IS BEFORE SCAN FOR 2.4GHZ
    {
        get_afterscanchannelno_2_4ghz=$(iw "$interface_2_4ghz" info | grep "channel" | awk '/channel/ {print $2}')
        max_attempts=10     ###WILL ONLY TRY FOR 10 TIMES MAX,TO AVOID LOOP PROBLEMS[LOOPFAIL-SAFE]
        attempts=0
            echo "#########2_4GHZ#########" | tee -a  "$log_savefor_runstatus"
        while [ "$get_afterscanchannelno_2_4ghz" != "$get_currentchannelno_2_4ghz" ] && [ "$attempts" -lt "$max_attempts" ]; do
            {
            echo "=>BEFORE SPECTRUM CHMETRIC SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_2_4ghz ~ AFTER SPECTRUM CHMETRIC SCAN-CHANNEL: $get_afterscanchannelno_2_4ghz"
            echo "=>MISMATCH, REDOING/REAPPLYING CHANGES"
            echo "=>CHANGES COMPLETED"
            } | tee -a  "$log_savefor_runstatus"
            sleep 3
            timeout -t 1 athssd -i "$wifiN_2_4ghz" -j "$interface_2_4ghz" -s "$get_currentchannelno_2_4ghz"
            ### Update the after-scan channel for the next iteration
            get_afterscanchannelno_2_4ghz=$(iw "$interface_2_4ghz" info | grep "channel" | awk '/channel/ {print $2}')
            ((attempts++))
        done
        {
        echo "=>BEFORE SPECTRUM CHMETRIC SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_2_4ghz ~ AFTER SPECTRUM CHMETRIC SCAN-CHANNEL: $get_afterscanchannelno_2_4ghz"
        echo "=>AP CHANNEL IS SET TO THE CHANNEL IT WAS BEFORE SCANNING FOR 2.4GHZ"
        echo "########################"
        echo "..."
        echo "..."
        echo "..."
        } | tee -a "$log_savefor_runstatus"
    }

    function channel_recheck_5ghz()     ###THIS FUNCTION CHECK FOR CHANNEL ,IT MAKE CHANNEL TO THAT IT IS BEFORE SCAN FOR 5GHZ
    {
        get_afterscanchannelno_5ghz=$(iw "$interface_5ghz" info | grep "channel" | awk '/channel/ {print $2}')
        max_attempts=10     ###WILL ONLY TRY FOR 10 TIMES MAX,TO AVOID LOOP PROBLEMS[LOOPFAIL-SAFE]
        attempts=0
            echo "##########5GHZ##########" | tee -a  "$log_savefor_runstatus"
        while [ "$get_afterscanchannelno_5ghz" != "$get_currentchannelno_5ghz" ] && [ "$attempts" -lt "$max_attempts" ]; do
        {
            echo "=>BEFORE SPECTRUM ANALYZER SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_5ghz ~ AFTER SPECTRUM ANALYZER SCAN-CHANNEL: $get_afterscanchannelno_5ghz"
            echo "=>MISMATCH, REDOING/REAPPLYING CHANGES"
            echo "=>CHANGES COMPLETED"
        } | tee -a  "$log_savefor_runstatus"
            sleep 3
            timeout -t 1 athssd -i "$wifiN_5ghz" -j "$interface_5ghz" -s "$get_currentchannelno_5ghz"
            ### Update the after-scan channel for the next iteration
            get_afterscanchannelno_5ghz=$(iw "$interface_5ghz" info | grep "channel" | awk '/channel/ {print $2}')
            ((attempts++))
        done
        {
        echo "=>BEFORE SPECTRUM ANALYZER SCAN-CHANNEL[AP DEFAULT]: $get_currentchannelno_5ghz ~ AFTER SPECTRUM ANALYZER SCAN-CHANNEL: $get_afterscanchannelno_5ghz"
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
        echo "##########################################################################################################################################"
        echo "=>SPECTRUM ANALYZER SCRIPT LAST RUN ON : $time IN APGUID $mac to generate report on Rssi-Interference report"
        echo "##########################################################################################################################################"
        } | tee -a "$log_savefor_runstatus"
    }
    ###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    topic="/spectrum_analyzer"      ### MQTT configuration
    ###################################################

    ###############################################################################################################################
    channel_utilization_fetcher() ### THIS GENERATES ADVANCE SPECTRUM CAPABILITES REPORT FOR CHANNEL UTILIZATION
    {
        tries=0
        max_tries=500
        ### FOR 2.4GHZ CHANNELS
        timeout -t 3 iwpriv wifi1 acs_2g_allch 1;timeout -t 3 iwpriv wifi1 acs_rank_en 1;timeout -t 3 iwpriv wifi1 acs_ctrlflags 0x1;timeout -t 3 iwpriv wifi1 acs_bkscanen 1;
        timeout -t 10 iwconfig "$interface_2_4ghz" channel 0;
        timeout -t 10 wifitool "$interface_2_4ghz" acsreport;
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
                echo "SAFETY~DEBUGGING FEATURE IF RF SCAN FAILS TO PROVIDE RESULT DUE TO VARIOUS REASONS"
                echo "Warning:athssd/acsreport is not generating Channel utilization,debug manually,or check in for ap driver/firmware or try again after sometimes"
                echo "TERMINATING..."
            } | tee -a "$log_save"
            exit 1
            fi
        fi
        done

        tries=0
        ### FOR 5GHZ CHANNELS
        timeout -t 3 iwpriv wifi0 acs_ctrlflags 0x1;timeout -t 3 iwpriv wifi0 acs_bkscanen 1;timeout -t 3 iwpriv wifi0 acs_rank_en 1;
        timeout -t 10 iwconfig "$interface_5ghz" channel 0;
        timeout -t 10 wifitool "$interface_5ghz" acsreport;
        sleep 9
        while true; do
        output=$(wifitool "$interface_5ghz" acsreport | grep -A1000 " The number of channels scanned for acs report is")
        if echo "$output" | grep "5180("; then
            echo "$output" > "$acsreport_5ghz_tablefile"
            break
        else
            tries=$((tries+1))
            if [ "$tries" -ge "$max_tries" ]; then
            {
                echo "SAFETY~DEBUGGING FEATURE IF RF SCAN FAILS TO PROVIDE RESULT DUE TO VARIOUS REASONS"
                echo "Warning:athssd/acsreport is not generating Channel utilization,debug manually,or check in for ap driver/firmware or try again after sometimes"
                echo "TERMINATING..."
            } | tee -a "$log_save"
            exit 1
            fi
        fi
        done
    }
    ###############################################################################################################################

    #############################################################
    ###spectral analysis data for 2.4ghz channel frequency
    #############################################################
    function athssd_json_maker_2_4ghz()
    {
        spectraltool -i "$wifiN_2_4ghz" stopscan;
        awk '/2412\(/ {flag=1; print; next} /ACS_/ {flag=0} flag' "$acsreport_2_4ghz_tablefile" > "$acsreport_temp_2_4ghz";
        sort -k2,2n -u "$acsreport_temp_2_4ghz" > "$temp_file_2_4ghz"; mv "$temp_file_2_4ghz" "$acsreport_temp_2_4ghz";
        IFS=$'\n'  ### Set Internal Field Separator to newline to iterate over lines
        function main_logic_2_4_ghz()
        {
            local attempts=0
            while [ "$attempts" -lt 30 ]; do
                output=$(timeout -t 1 athssd -i "$wifiN_2_4ghz" -j "$interface_2_4ghz" -s "$s" | grep -e "Spectral Classifier: Found Wi-Fi interference in" -e "Number")
                if [ -n "$output" ]; then
                    break
                fi
                attempts=$((attempts + 1))
            done
            if [ -z "$output" ]; then
                return    ### No data after 2 attempts, move to the next channel
            fi
            freq=$(echo "$output" | awk '/Found Wi-Fi interference/ {print $9}')
            #if [ -z "$freq" ]; then
                #return    ### Channel_frequency is empty, skip appending data
            #fi
            channel_info=$(awk '{gsub(/\([^(]*\)/, ""); print $1"="$5}' "$acsreport_temp_2_4ghz")
            noise_floor=$(echo "$channel_info" | grep "$freq" | cut -d "=" -f 2)
            channel_info2=$(awk -F' ' '{gsub(/[()]/, ""); print $1"="$2}' "$acsreport_temp_2_4ghz")
            channel_no=$(echo "$channel_info2" | grep "$freq" | cut -d "=" -f 2)
            if [ -z "$channel_no" ] || [ -z "$noise_floor" ]; then
                return    ### Skip appending data if channel_no or noise_floor is empty
            fi
            signal_strength=$(echo "$output" | awk '/Found Wi-Fi interference/ {print int($NF - 95)}')
            MinRssi=$(echo "$output" | awk '/Found Wi-Fi interference/ {print int($NF - 92)}')
            MaxRssi=$(echo "$output" | awk '/Found Wi-Fi interference/ {print int($NF - 98)}')
            mwo=$(echo "$output" | awk '/Number of MWO detection/ {print $NF}')
            wifi=$(echo "$output" | awk '/Number of WiFi detection/ {print $NF}')
            fhss=$(echo "$output" | awk '/Number of FHSS detection/ {print $NF}')
            cw=$(echo "$output" | awk '/Number of CW detection/ {print $NF}')
            ###DO NOT CHANGE THIS SEGMENT
            echo "{" >> "$filename_2_4ghz"
            echo "  \"Channel_Band\": \"2.4ghz\"," >> "$filename_2_4ghz"
            echo "  \"Channel_frequency\": \"$freq\"," >> "$filename_2_4ghz"
            echo "  \"channel_no\": \"$channel_no\"," >> "$filename_2_4ghz"
            echo "  \"noise_floor\": \"$noise_floor\"," >> "$filename_2_4ghz"
            echo "  \"time\": \"$time\"," >> "$filename_2_4ghz"
            echo "  \"APGUID\": \"$mac\"," >> "$filename_2_4ghz"
            echo "  \"Ifname\": \"$adjusted_interfacename_2_4ghz\"," >> "$filename_2_4ghz"
            echo "  \"Rssi\": \"$signal_strength\"," >> "$filename_2_4ghz"
            echo "  \"MinRssi\": \"$MinRssi\"," >> "$filename_2_4ghz"
            echo "  \"MaxRssi\": \"$MaxRssi\"," >> "$filename_2_4ghz"
            echo "  \"Number_of_MWO_detection\": \"$mwo\"," >> "$filename_2_4ghz"
            echo "  \"Number_of_WiFi_detection\": \"$wifi\"," >> "$filename_2_4ghz"
            echo "  \"Number_of_FHSS_detection\": \"$fhss\"," >> "$filename_2_4ghz"
            echo "  \"Number_of_CW_detection\": \"$cw\"" >> "$filename_2_4ghz"
            echo "}," >> "$filename_2_4ghz"
        }
        echo "[" >> "$filename_2_4ghz"
        for s in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
            main_logic_2_4_ghz
        done
        sed -i '$ s/,$//' "$filename_2_4ghz"
        echo "]" >> "$filename_2_4ghz"
        }

    #############################################################
    ###spectral analysis data for 5ghz channel frequency
    #############################################################
    function athssd_json_maker_5ghz()
    {
        spectraltool -i "$wifiN_5ghz" stopscan
        awk '/5180\(/ {flag=1; print; next} /ACS_/ {flag=0} flag' "$acsreport_5ghz_tablefile" > "$acsreport_temp_5ghz"
        sort -k2,2n -u "$acsreport_temp_5ghz" > "$temp_file_5ghz"
        mv "$temp_file_5ghz" "$acsreport_temp_5ghz"
        IFS=$'\n'   ### Set Internal Field Separator to newline to iterate over lines
        function main_logic_5ghz()
        {
            local attempts=0
            while [ "$attempts" -lt 3 ]; do
                output=$(timeout -t 1 athssd -i "$wifiN_5ghz" -j "$interface_5ghz" -s "$s" | grep -e "Spectral Classifier: Found Wi-Fi interference in" -e "Number")
                if [ -n "$output" ]; then
                    break
                fi
                attempts=$((attempts + 1))
            done
            if [ -z "$output" ]; then
                return   ### No data after 2 attempts, move to next channel
            fi
            freq=$(echo "$output" | awk '/Found Wi-Fi interference/ {print $9}')
            if [ -z "$freq" ]; then
                return   ### Channel_frequency is empty, skip appending data
            fi
            channel_info=$(awk '{gsub(/\([^(]*\)/, ""); print $1"="$5}' "$acsreport_temp_5ghz")     ### Use awk to get the channel frequency and its corresponding noise floor
            noise_floor=$(echo "$channel_info" | grep "$freq" | cut -d "=" -f 2)     ### Extract noise floor for the given frequency
            channel_info2=$(awk -F'[()]' '{print $1"="$2}' "$acsreport_temp_5ghz")        ### Use awk to get the channel frequency and its corresponding noise floor
            channel_no=$(echo "$channel_info2" | grep "$freq" | cut -d "=" -f 2)    ### Extract channel_no for the given frequency
            if [ -z "$channel_no" ] || [ -z "$noise_floor" ]; then
                return   ### Skip appending data if channel_no or noise_floor is empty
            fi
            signal_strength=$(echo "$output" | awk '/Found Wi-Fi interference/ {print int($NF - 95)}')
            MinRssi=$(echo "$output" | awk '/Found Wi-Fi interference/ {print int($NF - 92)}')
            MaxRssi=$(echo "$output" | awk '/Found Wi-Fi interference/ {print int($NF - 98)}')
            mwo=$(echo "$output" | awk '/Number of MWO detection/ {print $NF}')
            wifi=$(echo "$output" | awk '/Number of WiFi detection/ {print $NF}')
            fhss=$(echo "$output" | awk '/Number of FHSS detection/ {print $NF}')
            cw=$(echo "$output" | awk '/Number of CW detection/ {print $NF}')
            ###DO NOT CHANGE THIS SEGMENT
            echo "{" >> "$filename_5ghz"
            echo "  \"Channel_Band\": \"5ghz\"," >> "$filename_5ghz"
            echo "  \"Channel_frequency\": \"$freq\"," >> "$filename_5ghz"
            echo "  \"channel_no\": \"$channel_no\"," >> "$filename_5ghz"
            echo "  \"noise_floor\": \"$noise_floor\"," >> "$filename_5ghz"
            echo "  \"time\": \"$time\"," >> "$filename_5ghz"
            echo "  \"APGUID\": \"$mac\"," >> "$filename_5ghz"
            echo "  \"Ifname\": \"$adjusted_interfacename_5ghz\"," >> "$filename_5ghz"
            echo "  \"Rssi\": \"$signal_strength\"," >> "$filename_5ghz"
            echo "  \"MinRssi\": \"$MinRssi\"," >> "$filename_5ghz"
            echo "  \"MaxRssi\": \"$MaxRssi\"," >> "$filename_5ghz"
            echo "  \"Number_of_MWO_detection\": \"$mwo\"," >> "$filename_5ghz"
            echo "  \"Number_of_WiFi_detection\": \"$wifi\"," >> "$filename_5ghz"
            echo "  \"Number_of_FHSS_detection\": \"$fhss\"," >> "$filename_5ghz"
            echo "  \"Number_of_CW_detection\": \"$cw\"" >> "$filename_5ghz"
            echo "}," >> "$filename_5ghz"
        }
        echo "[" >> "$filename_5ghz"
        for s in 36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 149 153 157 161 165 169 173; do
            main_logic_5ghz
        done
        sed -i '$ s/,$//' "$filename_5ghz"
        echo "]" >> "$filename_5ghz"
        }

    ###################################################################################################################################################
    ### THIS FUNCTION SEND DATA TO CLOUD VIA MQTT BY READING FROM SPECIFIED FILES
    ###################################################################################################################################################
    function send_data_via_mqtt_2_4GHz()
    {
        json_file_2_4ghz_cu="$filename_2_4ghz";json_data_2_4ghz_cu=$(cat "$json_file_2_4ghz_cu");
            ### Send data to MQTT topic
            if [ -z "$json_data_2_4ghz_cu" ];       ### Check if json_data_2_4ghz_cu is empty
            then
                echo "json_data_2_4ghz_cu is empty"
            else
                if echo "$json_data_2_4ghz_cu" | grep "Channel_frequency";      ### Check if json_data_3_4ghz_cu contains specific elements (e.g., channel and frequency)
                then
                    echo "json_data_2_4ghz_cu contains channel and frequency"
                    timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_data_2_4ghz_cu" -r
                else
                    echo "json_data_2_4ghz_cu does not contain channel and frequency"
                fi
            fi
    }

    function send_data_via_mqtt_5GHz()
    {
        json_file_5ghz_cu="$filename_5ghz";json_data_5ghz_cu=$(cat "$json_file_5ghz_cu");
            if [ -z "$json_data_5ghz_cu" ];     ### Check if json_data_5ghz_cu is empty
            then
                echo "json_data_5ghz_cu is empty"
            else
                if echo "$json_data_5ghz_cu" | grep "Channel_frequency";    ### Check if json_data_5ghz_cu contains specific elements (e.g., channel and frequency)
                then
                    echo "json_data_5ghz_cu contains channel and frequency"
                    timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_data_5ghz_cu"  -r
                else
                    echo "json_data_5ghz_cu does not contain channel and frequency"
                fi
            fi
    }
    timeout -t 15 sh /usr/lib/lua/luci/Modules/MQTT_Pub.sh -t "$topic" -m "$json_data_2_4ghz_cu" -r
    ###################################################################################################################################################
    ###################################################################################################################################################
    function main_body()
    {
        ###MAIN IF LOGIC CONDITION TO CALL FUNCTION AS PER MODEL   <<<<========== MAIN BODY RESPONSIBLE FOR ACTUAL CALLING OF REQUIRED FUNTION BASED ON AP MODELS
        if grep -qE "QN-(H-245.*|O-230.*|I-220.*|O-240.*|H-250.*|I-270.*|I-280.*|I-290.*|O-290.*|I-470.*|I-480.*|O-480.*|I-490.*|O-490.*)" /etc/model;  ### Check if the grep result matches the desired patterns
        then
        time="";
        time=$(date +"%d-%m-%Y %I:%M:%S %p");        ### Get the latest current date and time
        echo -n "" > "$filename_2_4ghz";echo -n "" > "$filename_5ghz";echo -n "" > "$acsreport_2_4ghz_tablefile";echo -n "" > "$acsreport_5ghz_tablefile";echo -n "" > "$acsreport_temp_2_4ghz";echo -n "" > "$acsreport_temp_5ghz";echo -n "" > "$temp_file_2_4ghz";echo -n "" > "$temp_file_5ghz";
        channel_utilization_fetcher
        athssd_json_maker_2_4ghz
        send_data_via_mqtt_2_4GHz
        #athssd_json_maker_5ghz
        #send_data_via_mqtt_5GHz
        rm -rf "${filename_2_4ghz}" "${filename_5ghz}" "${acsreport_2_4ghz_tablefile}" "${acsreport_5ghz_tablefile}" "${acsreport_temp_2_4ghz}" "${acsreport_temp_5ghz}" "${temp_file_2_4ghz}" "${temp_file_5ghz}"
        elif grep "QN-I-210*" /etc/model;   ###condition because generates different format acsreport
        then
            echo "i-210 MOdels are not supported as they are not qsdk based,use their default tools for spectral analysis"
            exit 0;
        else
            echo "Model does not match the specified conditions."
            exit 0;
        fi
    }

    counter_handler()
    {
        timeout_interval=$(( timeout_interval ))
        if [ "$timeout_interval" -ge 305 ]; then
            echo "Error: Timeout interval exceeded,Gui input got more than or equal to current threshold of 5 minutes" | tee -a "$log_save"
            exit 0
        else
            echo "Timeout interval is within limits,procedding"
        fi
        max_iterations=108       ### Set maximum number of iterations
        iteration_counter=0
        while [ "$iteration_counter" -lt "$max_iterations" ]; do
            ((iteration_counter++))       ### Increment the iteration counter
            start_time=$(date +"%s")        ### Get current time in epoch format
            end_time=$((start_time + timeout_interval))     ### Calculate end time based on timeout_interval
            while [ "$(date +"%s")" -lt "$end_time" ]; do       ### Run loop until end time is reached
                timeout -t 3 spectraltool -i "$wifiN_2_4ghz" stopscan;timeout -t 3 spectraltool -i "$wifiN_5ghz" stopscan;
                main_body
                timeout -t 3 spectraltool -i "$wifiN_2_4ghz" stopscan;timeout -t 3 spectraltool -i "$wifiN_5ghz" stopscan;  ### Stop scans and perform cleanup
            done
            break   ### Exit the loop if executed at least once
        done
        timeout -t 3 iwpriv wifi1 acs_2g_allch 0;timeout -t 3 iwpriv wifi1 acs_rank_en 0;timeout -t 3 iwpriv wifi1 acs_ctrlflags 0x0;timeout -t 3 iwpriv wifi1 acs_bkscanen 0;
        timeout -t 3 iwpriv wifi0 acs_rank_en 0;timeout -t 3 iwpriv wifi0 acs_ctrlflags 0x0;timeout -t 3 iwpriv wifi0 acs_bkscanen 0;
        echo "" > "$log_savefor_runstatus"
        channel_recheck_2_4ghz
        channel_recheck_5ghz
        runstatus_log
        rm -rf "$main_directory"    ###REMOVE ALL TEMPORARY FILES AND DATAPROCESSING FILES FROM MAIN DIRECTORY LOCATED IN "/tmp/"
        echo "EVERY PROCESS EXECUTED SUCCESSFULLY WITHOUT ANY ISSUES,ON LAST RECORED TIME ON : $time" | tee -a  "$log_save"
        exit 0
    }

    #### THIS FUCNTION CHECKS IF SCRIPT IS PROVIDED WITH ARGUMENT OF 1/0 TO MAKE IT IN STATE OF ENABLE/DISABLE
    function initialize_SCBHC752K()
    {
        timeout_interval="$2"
        if [ -n "$1" ]; then    ### If argument is provided, execute code based on the argument
            if [ "$1" == "1" ]; then
                echo "Running the script with argument '1' ";
                counter_handler;
            else
                echo "Invalid argument provided. Exiting";
                exit 0;
            fi
        else
            echo "Provide Valid Arguments. Exiting...";
        fi
    }
    initialize_SCBHC752K "$1" "$2"
    ###################################################################################################################################################
    echo "Running spectrum_analyzer.sh"s
    rm -f "$LOCK_FILE"  ### Release the lock
    trap - INT TERM EXIT
else
    echo "Script is already running in background, exiting."
    exit 1
fi
###################################################################################################################################################
###///END_OF_FILE
EOF
)
echo "$script_content_radio_frequencies" > "/tmp/all_spectrumdata/spectrum_analyzer_runoncommand"
}


function thread_manager_for_2_4ghz_and_5ghz_bands()
{
if [ "$1" -eq 1 ]; then
    command="$1"
    time_duration="$2"
    band_2_4GHz_and_5GHz_thread
    sh "/tmp/all_spectrumdata/spectrum_analyzer_runoncommand" "$command" "$time_duration" && rm "/tmp/all_spectrumdata/spectrum_analyzer_runoncommand" &
elif [ "$1" -eq 0 ]; then
    timeout -t 8 pkill -f "/tmp/all_spectrumdata/spectrum_analyzer_runoncommand";
    rm /tmp/all_spectrumdata/spectrum_analyzer/acsreport_2_4ghz && rm /tmp/all_spectrumdata/spectrum_analyzer/acsreport_5ghz
    rm /tmp/all_spectrumdata/spectrum_analyzer/iwconfigtemp && rm /tmp/all_spectrumdata/spectrum_analyzer/rmtemp_2_4ghz
    rm /tmp/all_spectrumdata/spectrum_analyzer/rmtemp_5ghz && rm /tmp/all_spectrumdata/spectrum_analyzer/spectral_data_2_4ghz.json
    rm /tmp/all_spectrumdata/spectrum_analyzer/spectral_data_5ghz.json && rm /tmp/all_spectrumdata/spectrum_analyzer/temp_2_4ghz.txt
    rm /tmp/all_spectrumdata/spectrum_analyzer/temp_5ghz.txt
    sleep 3
    defaultchannel_set_onkill_2_4GHz=$(cat /tmp/all_spectrumdata/spectrum_analyzer/defaultchannel_2_4GHz); defaultchannel_set_onkill_5GHz=$(cat /tmp/all_spectrumdata/spectrum_analyzer/defaultchannel_5GHz);
    timeout -t 1 athssd -i "$wifiN_2_4ghz" -j "$interface_2_4ghz" -s "$defaultchannel_set_onkill_2_4GHz"
    timeout -t 1 athssd -i "$wifiN_5ghz" -j "$interface_5ghz" -s "$defaultchannel_set_onkill_5GHz"
else
    echo "Invalid input"
    exit 1
fi
}
thread_manager_for_2_4ghz_and_5ghz_bands "$1" "$2"
###################################################################################################################################################
###///END_OF_FILE