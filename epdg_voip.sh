#!/bin/bash
###|================================================================================================================================================================================
###|FILE                                 :  epdg_voip.sh
###|OTHER_FILES_CREATION_AND_DEPENDENCY  :  $wifi_calling_saved_json,epdg_voip_refresh.sh,epdg_tc.sh
###|PACKAGE DEPENDENCY                   :  tc[traffic control],iptables,jq,sed,bash utilities
###|PATH                                 :  /usr/lib/lua/luci/AP/epdg_voip.sh
###|USAGE                                :  give priority 1 to epdg wifi calling
###|ARGUMENTS            #TURN_ON-EX     :  sh /usr/lib/lua/luci/AP/epdg_voip.sh '{"wlan":"WLAN2789","WifiCalling":1,"profile_id":"c4ca4238a0b923820dcc509a6f75849b","RevisionNo}'
###                      #TURN_OFF-EX    :  sh /usr/lib/lua/luci/AP/epdg_voip.sh '{"wlan":"WLAN2926","WifiCalling":0,"profile_id":"","RevisionNo":853}'
###                      #TURN_EDIT-EX   :  sh /usr/lib/lua/luci/AP/epdg_voip.sh '{"wlan":"","WifiCalling":1,"profile_id":"c4ca4238a0b923820dcc509a6f75849b","RevisionNo}'
###|================================================================================================================================================================================
####################################################################################################################################################################################

###///START_OF_FILE
###////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
###LOCKING SCRIPT TO PREVENT REDUNDANT/DUPLICATE PROCESSES FROM EXECUTING IN THE BACKGROUND,HELPFUL IN AVOIDING MULTIPLE INSTANCES OF THE SAME SCRIPT RUNNING
###SIMULTANEOUSLY IF REQUESTED,MULTIPLE TIMES BY THE USER IN THE CLOUD, WHETHER INTENTIONALLY OR ACCIDENTALLY.
LOCK_FILE="/var/run/epdg_voip.lock"       ###LOCK INITIATING
if ( set -o noclobber; echo "$$" > "$LOCK_FILE") 2> /dev/null;  ###LOCK CONDITION CHECK
then
    trap 'rm -f "$LOCK_FILE"; exit $?' INT TERM EXIT
        #########################################################
        ###GLOBAL VARIABLE
        #########################################################
            temp_directory="/tmp/wificalling"
            mkdir -p "$temp_directory"
            mkdir -p "/usr/lib/lua/luci/epdg_voip/"
            wifi_calling_saved_rules="/usr/lib/lua/luci/epdg_voip/epdg_tc.sh"   ###only this file will be saved in "/usr/lib/lua/luci/epdg_voip/",rest will be in "/tmp/"
            wifi_calling_saved_json="/usr/lib/lua/luci/epdg_voip/epdg_void_data.json"   ###only this file will be saved in "/usr/lib/lua/luci/epdg_voip/",rest will be in "/tmp/"
            data_file="$wifi_calling_saved_json"
            output_file="$wifi_calling_saved_json"
            temp_file=$temp_directory/epdg_void_datatmp.json
            datatmp_file=$temp_directory/epdg_void_datatmp.json
            log_save="/tmp/epdg_voip.log"
            echo -n "" > "$log_save"  ###clear logfile data on start
            echo -n "" > "/tmp/wificalling/epdg_void_data_tempX2.json"  ###clear file data on start
        ###//////////////////////////////////////////////////////

        #####################
        ######FUNCTIONS:
        #####################
            check_packages()
            {
                if which tee >/dev/null && which jq >/dev/null && which tc >/dev/null && which iptables >/dev/null; then
                    echo "All required packages (tee, jq, tc, iptables) are installed."
                else
                    if ! which tee >/dev/null; then
                        echo "tee is not installed." | tee -a "$log_save"
                    fi
                    if ! which jq >/dev/null; then
                        echo "jq is not installed." | tee -a "$log_save"
                    fi
                    if ! which tc >/dev/null; then
                        echo "tc is not installed." | tee -a "$log_save"
                    fi
                    if ! which iptables >/dev/null; then
                        echo "iptables is not installed." | tee -a "$log_save"
                    fi
                    exit 0
                fi
                }
            check_packages

            ###CREATING FUNCTION TO FLUSH PREVIOUS RULES:
            cleanup_previous_rules()
            {
                sed -i -e '/#EPDG_VOIP/d; /^$/d' -e '/#EPDG_TC/d; /^$/d' "$wifi_calling_saved_rules" | tee -a /dev/null
            }
            ###CREATING FUNCTION TO REMOVE RULES APPLIED AND SAVED IN "epdg_tc.sh":
            cleanup_config_rules()
            {
                echo -n "" > "$wifi_calling_saved_rules"
            }
            ###CREATING FUNCTION TO CREATE RULES TO BE APPLIED IN IPTABLES:
            configure_iptables_rules()
            {
                if [[ -n "$mnc" && -n "$mcc" && -n "$dscp_main" ]]; then
                {
                    echo "iptables -w -t mangle -N EPDG_VOIP-CHAIN #EPDG_VOIP"
                    echo "iptables -w -t mangle -I EPDG_VOIP-CHAIN -d 'epdg.epc.mnc${mnc}.mcc${mcc}.pub.3gppnetwork.org' -j DSCP --set-dscp ${dscp_main} #EPDG_VOIP"
                    echo "iptables -w -t mangle -I EPDG_VOIP-CHAIN -s 'epdg.epc.mnc${mnc}.mcc${mcc}.pub.3gppnetwork.org' -j DSCP --set-dscp ${dscp_main} #EPDG_VOIP"
                    echo "iptables -w -t mangle -I EPDG_VOIP-CHAIN -m dscp --dscp $dscp_main -j MARK --set-mark 39000 #EPDG_VOIP"
                    echo "iptables -w -t mangle -I PREROUTING -j EPDG_VOIP-CHAIN #EPDG_VOIP"
                    echo "iptables -w -t mangle -I POSTROUTING -j EPDG_VOIP-CHAIN #EPDG_VOIP"
                } | tee -a "$wifi_calling_saved_rules"
                    else
                    echo "Error: Missing required parameters (mnc, mcc, dscp_main). Cannot configure iptables rules,check configure_iptables_rules-function" | tee -a "$log_save"
                    exit 0
                fi
            }


            ###CREATING FUNCTION TO APPLY TC RULES:
            configure_tc_rules()
            {
                    if [[ -z "$interface" ]]; then
                        echo "Error: Interface variable is empty. Cannot configure TC rules,check configure_tc_rules-function"  | tee -a "$log_save"
                        exit 0
                    fi
                {
                ###root htb
                echo "tc qdisc add dev $interface root handle 1: htb default 1 direct_qlen 30000 #EPDG_TC"
                echo "tc qdisc add dev $interface ingress #EPDG_TC"
                ###class
                echo "tc class add dev $interface parent 1:1 classid 1:10 htb rate 1000000000mbit ceil 1000000000mbit burst 1500b cburst 1500b #EPDG_TC"
                ###filter
                echo "tc filter add dev $interface parent 1:0 protocol ip prio 1 handle 39000 fw classid 1:10 #EPDG_TC"
                echo "tc filter add dev $interface parent 1:0 protocol ip prio 1 handle 39000 fw flowid 1:10 #EPDG_TC"
                echo "tc filter add dev $interface parent 1:1 protocol ip prio 1 handle 39000 fw classid 1:10 #EPDG_TC"
                echo "tc filter add dev $interface parent 1:1 protocol ip prio 1 handle 39000 fw flowid 1:10 #EPDG_TC"
                ###parent-sfq
                echo "tc qdisc add dev $interface parent 1:10 handle 39000: sfq perturb 1 #EPDG_TC"
                } | tee -a "$wifi_calling_saved_rules"
            }


            ###REMOVE TC RULES ON DELETE:
            deconfigure_iptables_tc()
            {
                if [ -z "$wifi_calling_saved_rules" ]; then
                    echo "Parameter 'wifi_calling_saved_rules' is not fetched,exiting,Problem occured while running deconfigure_iptables_tc function" | tee -a "$log_save"
                    exit 0
                fi
                while read -r line; do
                    modified_line=$(echo "$line" | sed 's/add/del/g; s/-I /-D /g')
                    modified_line2=$(echo "$line" | sed 's/add/del/g; s/-N /-D /g')
                    eval "$modified_line"
                    eval "$modified_line2"
                    echo "Executed: $modified_line AND $modified_line2"
                done < "$wifi_calling_saved_rules"
                iptables -t mangle -F EPDG_VOIP-CHAIN
                echo "Deconfiguration applied successfully."
            }


            ###FUNCTION TO REMOVE DUPLICACY/REDUNDANCY
            unique()
            {
                        awk '!seen[$0]++' "$wifi_calling_saved_rules" > tmp_file1 && mv tmp_file1 "$wifi_calling_saved_rules"
                        awk '!seen[$0]++' "$wifi_calling_saved_json" > tmp_file2 && mv tmp_file2 "$wifi_calling_saved_json"
            }


            ###CREATING FUNCTION TO APPLY MAIN RULES:
            todo()
                {
                    ##cleanup_config_rules
                    while IFS= read -r json_string;
                    do
                        mnc=$(echo "$json_string" | jq -r '.MNC')
                        mcc=$(echo "$json_string" | jq -r '.MCC')
                        dscp=$(echo "$json_string" | jq -r '.dscp')
                        interface=$(echo "$json_string" | jq -r '.ssid_interface')
                        mainprofile=$(echo "$json_string" | jq -r '.Old_profile_name')
                        wlan_list_main=$(echo "$json_string" | jq -r '.wlan_list')
                        event=$(echo "$json_string" | jq -r '.Event')

                        case "$dscp" in
                            "Video") dscp_main=40 ;;
                            "Voice") dscp_main=46 ;;
                            "Best_Effort") dscp_main=0 ;;
                            "Background") dscp_main=8 ;;
                            *) dscp_main=0 ;;
                        esac

                        pos_2="$(uci show wireless | grep ".name='$wlan_list_main.*_2'" | cut -f 2 -d .)"
                        pos_5="$(uci show wireless | grep ".name='$wlan_list_main.*_5'" | cut -f 2 -d .)"
                        if [ -n "$interface" ] && [ "$event" == '1' ];
                        then
                            uci set wireless."$pos_2".epdg_voip_profile="$mainprofile"
                            uci set wireless."$pos_5".epdg_voip_profile="$mainprofile"
                            uci set wireless."$pos_2".epdg_voip="1"
                            uci set wireless."$pos_5".epdg_voip="1"
                            uci commit wireless
                            configure_iptables_rules        ###function-call
                            configure_tc_rules              ###function-call
                        else
                            cleanup_config_rules         ###function-call
                            cleanup_previous_rules       ###function-call
                        fi
                    done < "$wifi_calling_saved_json"
                }


            ###ENSURE MNC IS THREE DIGITS BY ADDING LEADING ZEROS,IF NOT ALREADY 3 DIGITS MNC RETRIEVE FROM CLOUD,[REQUIRED FOR IPTABLES APPLICATION FOR 3DIGIT MNC VALUE]
            function_roundoff()
            {
                    ### Check if the JSON file exists
                    if [ ! -f "$wifi_calling_saved_json" ]; then
                        echo "JSON file not found: $wifi_calling_saved_json,EXISTING,check function_roundoff-function" | tee -a "$log_save"
                        exit 0
                    fi
                    ### Temporary file to store modified JSON data
                    temp_file=$(mktemp)
                        ### Read and process each JSON object from the file
                        while read -r json_object; do
                            ### Extract MNC value
                            mnc=$(echo "$json_object" | jq -r '.MNC')
                            ### Ensure MNC is three digits by adding leading zeros
                            mnc_fixed=$(printf "%03d" "$mnc")
                            ### Replace the original MNC with the fixed MNC in the JSON object and use compact output
                            modified_json_object=$(echo "$json_object" | jq ".MNC=\"$mnc_fixed\"" -c)
                            ### Append the modified JSON object to the temporary file
                            echo "$modified_json_object" >> "$temp_file"
                        done < "$wifi_calling_saved_json"
                    ### Overwrite the original JSON file with the modified data
                    mv "$temp_file" "$wifi_calling_saved_json"
                    ### Clean up the temporary file
                    rm -rf "$temp_file"
                    echo "JSON file updated: $wifi_calling_saved_json"
            }
        #######################################################################################################################

            #######################################################################################################################
            ###MODULE-1:Function to extract JSON field using jq
            #######################################################################################################################
            extract_json_field()
            {
                local json="$1"
                local field="$2"
                ### Check if json or field variables are empty
                if [ -z "$json" ] || [ -z "$field" ]; then
                    echo "Error: JSON or field variable is empty,check extract_json_field-function" | tee -a "$log_save"
                    exit 0
                fi
                echo "$json" | jq -r ".$field"
            }

            ###FUNCTION TO RETRIEVE WLAN INTERFACES AS JSON
            get_wlan_interfaces_json()
            {
                local wlan="$1"
                local interface_list=""
                for network in $(echo "$wlan" | tr ',' ' '); do
                    interface=$(uci show wireless | grep -A1 -F -e "$network" | awk -F'=' '/\.ifname/ {gsub(/'\''/, "", $2); printf("%s,", $2)}')
                    interface_list="${interface_list}${interface}"
                done
                ### Create a JSON object with the WLAN interfaces
                echo "{\"interfaces\":\"${interface_list%,}\"}"
            }

            ###FUNCTION TO PROCESS AND APPEND JSON DATA FOR A WLAN
            process_and_append_json()
            {
                local json_file="$1"
                local tmp_file="$2"
                local wlan="$3"
                local action="$4"
                local profile_id="$5"

                ### Check if any of the required variables are empty
                if [ -z "$json_file" ] || [ -z "$tmp_file" ] || [ -z "$action" ] || [ -z "$profile_id" ]; then
                    echo "Error: One or more required variables are empty,check process_and_append_json-function" | tee -a "$log_save"
                    exit 0
                fi

                ### Read and process JSON lines
                while IFS= read -r line; do
                    ### Parse the JSON data
                    mnc_value=$(echo "$line" | jq -r '.MNC')
                    ### Check if MNC is a 3-digit value
                    if [[ "$mnc_value" =~ ^[0-9]{3}$ ]];
                    then
                        ### MNC is already a 3-digit value, no modification needed
                        modified_line="$line"
                    else
                        ### Add leading zeros to make it a 3-digit value
                        modified_mnc=$(printf "%03d" "$mnc_value")
                        ### Modify the line with the updated MNC value
                        modified_line=$(echo "$line" | jq ".MNC=\"$modified_mnc\"")
                    fi
                    ### Print the modified line to the console
                    echo "$modified_line"
                done < "$json_file" > "$tmp_file"
                ### Append the modified content to the output file
                cat "$tmp_file" >> "$output_file"
            }

            json_string="$1"
            ### Main script starts here
            echo "$json_string"
            wlan_list=$(extract_json_field "$json_string" 'wlan')
            action=$(extract_json_field "$json_string" 'WifiCalling')
            profile_id=$(extract_json_field "$json_string" 'profile_id')
            Revision_No=$(extract_json_field "$json_string" 'RevisionNo')

            echo "######################################################################" | tee -a "$log_save"
            echo "==>Last updated Wifi_Calling Revision Number is: $Revision_No" | tee -a "$log_save"
            echo "######################################################################" | tee -a "$log_save"

            [ "$Revision_No" -gt '0' ] && echo "$Revision_No" > /etc/RevisionNo

            sed -i "/\"wlan_list\":\"$wlan_list\"/d" "$wifi_calling_saved_json"
            deconfigure_iptables_tc     ###function-call
            output_file="$wifi_calling_saved_json"

            if [ "$wlan_list" == "" ]; then
                input_file="$wifi_calling_saved_json"
                temp_file="/tmp/wificalling/epdg_void_datatmp.json"
                api_request="{\"id\":\"$profile_id\"}"
                api_response=$(fireapi -a /api/v1/get_wifi_calling_profile_data -d "$api_request" -j)
                edited_profile_name=$(echo "$api_response" | jq -r '.data."Profile_Name"')

                sed -i "/\"wlan_list\":\"$wlan_list\"/d" "$temp_file"
                while read -r json_string; do
                output=$(echo "$api_response" | jq -c -r --arg action_main "$action" --arg wlan_value "$wlan_value" --arg interface "$ssid_interface" --arg revision_no "$Revision_No" --arg profile_id "$profile_id" '
                        .data.Profile_Name as $profile |
                        .data.DataArray[] |
                        {
                            "Event": $action_main,
                            "Old_profile_name": $profile,
                            "MNC": .MNC,
                            "MCC": .MCC,
                            "dscp": .QosPriority,
                            "wlan_list": $wlan_value,
                            "ssid_interface": $interface,
                            "Revision_No": $revision_no,
                            "Profile_ID": $profile_id
                        } | @json'
                )
                    echo "$output" >> "$temp_file"
                done < "$input_file"

                ###=======================================================================================================================ON-EDIT PROFILE FOR GUI
                echo -n "" > "/tmp/wificalling/epdg_void_data_tempX2.json"
                cat "$wifi_calling_saved_json" >> "/tmp/wificalling/epdg_void_data_tempX2.json"
                sed -i "/\"Old_profile_name\":\"$edited_profile_name\"/d" /tmp/wificalling/epdg_void_data_tempX2.json
                awk awk -F'[:,]' '!seen[$2$4$6$8$10$12$14]++' /tmp/wificalling/epdg_void_data_tempX2.json > tmp_file5x && mv tmp_file5x /tmp/wificalling/epdg_void_data_tempX2.json
                ###=======================================================================================================================

                # Define the paths to the JSON files                data_file="$wifi_calling_saved_json"
                datatmp_file="/tmp/wificalling/epdg_void_datatmp.json"
                temp_file="/tmp/wificalling/epdg_void_datatmpopr.txt"
                while read -r line_data; do
                    old_profile_name=$(echo "$line_data" | jq -r '.Old_profile_name')
                    wlan_list=$(echo "$line_data" | jq -r '.wlan_list')
                    ssid_interface=$(echo "$line_data" | jq -r '.ssid_interface')
                    sed -i "/\"wlan_list\":\"$wlan_list\"/d" "$wifi_calling_saved_json"         ###profile add/delete/edit value on changes effect on result
                    # Read data from epdg_void_datatmp.json and update if condition matches
                    while read -r line_datatmp; do
                        if [[ $(echo "$line_datatmp" | jq -r '.Old_profile_name') == "$old_profile_name" ]]; then
                        # Update wlan_list and ssid_interface
                        line_datatmp=$(echo "$line_datatmp" | jq -c ".wlan_list=\"$wlan_list\" | .ssid_interface=\"$ssid_interface\"")
                        fi
                        echo "$line_datatmp" >> "$temp_file"
                    done < "$datatmp_file"
                    # Add a newline character after each JSON object
                    echo "" >> "$temp_file"
                done < "$data_file"

                # Replace the original datatmp file with the updated data
                mv "$temp_file" "$datatmp_file"
                # Clean up temporary file

                awk '!seen[$0]++' /tmp/wificalling/epdg_void_datatmp.json > tmp_file5 && mv tmp_file5 /tmp/wificalling/epdg_void_datatmp.json
                sed -i '/"wlan_list":""/d' /tmp/wificalling/epdg_void_datatmp.json
                sort -o /tmp/wificalling/epdg_void_datatmp.json /tmp/wificalling/epdg_void_datatmp.json
                sed -i '/^ *$/d' /tmp/wificalling/epdg_void_datatmp.json

                ###TRANFER AFTER EDIT<===MAIN
                awk -F'[:,]' '!seen[$2$4$6$8$10$12$14]++' "$wifi_calling_saved_json" > tmp_file6x && mv tmp_file6x "$wifi_calling_saved_json"
                cat "/tmp/wificalling/epdg_void_datatmp.json" >> "$wifi_calling_saved_json"
                awk -F'[:,]' '!seen[$2$4$6$8$10$12$14]++' /tmp/wificalling/epdg_void_data_tempX2.json > tmp_file7x && mv tmp_file7x /tmp/wificalling/epdg_void_data_tempX2.json
                cat /tmp/wificalling/epdg_void_data_tempX2.json >> "$wifi_calling_saved_json"
                echo -n "" > "/tmp/wificalling/epdg_void_data_tempX2.json"
                rm -rf tmp_file5 tmp_file5x tmp_file6x tmp_file7x       ###removing temp files
                rm -rf /tmp/wificalling/epdg_void_datatmp.json
                deconfigure_iptables_tc       ###function-call
                cleanup_config_rules            ###function-call
                cleanup_previous_rules          ###function-call
                function_roundoff           ###function-call
                unique              ###function-call
                todo            ###function-call
                unique      ###function-call
                rm -rf "/tmp/wificalling/epdg_void_data_tempX2.json"
            else
                # Loop through WLAN values
                for wlan_value in $(echo "$wlan_list" | tr ',' ' '); do
                    wlan_interfaces=$(get_wlan_interfaces_json "$wlan_value")
                    interfaces=$(echo "$wlan_interfaces" | jq -r '.interfaces')
                    api_request="{\"id\":\"$profile_id\"}"
                    api_response=$(fireapi -a /api/v1/get_wifi_calling_profile_data -d "$api_request" -j)

                    # Loop through individual ssid_interface values
                    for ssid_interface in $(echo "$interfaces" | tr ',' ' '); do
                        if [ "$action" -eq 0 ] && [ "$wlan_list" ]; then
                            awk -v wlan="$wlan_value" '$0 !~ wlan' "$data_file" > "$data_file.temp"
                            mv "$data_file.temp" "$data_file"
                            while iptables -t mangle -L PREROUTING | grep -q EPDG_VOIP-CHAIN || iptables -t mangle -L POSTROUTING | grep -q EPDG_VOIP-CHAIN;
                            do iptables -t mangle -D PREROUTING -p all -j EPDG_VOIP-CHAIN && iptables -t mangle -D POSTROUTING -p all -j EPDG_VOIP-CHAIN;
                            done
                            pos_2="$(uci show wireless | grep ".name='$wlan_list.*_2'" | cut -f 2 -d .)"
                            pos_5="$(uci show wireless | grep ".name='$wlan_list.*_5'" | cut -f 2 -d .)"
                            uci delete wireless."$pos_2".epdg_voip_profile="$profile"
                            uci delete wireless."$pos_5".epdg_voip_profile="$profile"
                            uci set wireless."$pos_2".epdg_voip="0"
                            uci set wireless."$pos_5".epdg_voip="0"
                            uci commit wireless
                            deconfigure_iptables_tc     ###function-call
                            cleanup_config_rules        ###function-call
                            cleanup_previous_rules      ###function-call
                            todo        ###function-call
                        else
                            while iptables -t mangle -L PREROUTING | grep -q EPDG_VOIP-CHAIN || iptables -t mangle -L POSTROUTING | grep -q EPDG_VOIP-CHAIN;
                            do iptables -t mangle -D PREROUTING -p all -j EPDG_VOIP-CHAIN && iptables -t mangle -D POSTROUTING -p all -j EPDG_VOIP-CHAIN;
                            done
                            output=$(echo "$api_response" | jq -c -r --arg action_main "$action" --arg wlan_value "$wlan_value" --arg interface "$ssid_interface" --arg revision_no "$Revision_No" --arg profile_id "$profile_id" '
                                    .data.Profile_Name as $profile |
                                    .data.DataArray[] |
                                    {
                                        "Event": $action_main,
                                        "Old_profile_name": $profile,
                                        "MNC": .MNC,
                                        "MCC": .MCC,
                                        "dscp": .QosPriority,
                                        "wlan_list": $wlan_value,
                                        "ssid_interface": $interface,
                                        "Revision_No": $revision_no,
                                        "Profile_ID": $profile_id
                                    } | @json'
                            )
                            echo "$output" >> "$output_file"
                            function_roundoff       ###function-call
                            unique      ###function-call
                            todo        ###function-call
                            unique      ###function-call
                            fi
                          done
                        done
                    fi
                    sh -x "$wifi_calling_saved_rules"
                        ###WILL ONLY RUN IF REQUIRED CONDITION IS SATISFIED
                        wlan_list_edited=$(echo "$1" | jq -r '.wlan')
                        if [ "$wlan_list_edited" == "" ]; then
                        new_operation="$1"
                        get_profile_id=$(echo "$new_operation" | jq -r '.profile_id')
                        revisiono_new=$(echo "$new_operation" | jq -r '.RevisionNo')
                        api_request="{\"id\":\"$get_profile_id\"}"
                        api_response=$(fireapi -a /api/v1/get_wifi_calling_profile_data -d "$api_request" -j)
                        ###get_neweditedprofilename=$(echo "$api_response" | jq -r '.data.Profile_Name')

                            tmp_file=$(mktemp)
                            while IFS= read -r line; do
                                ### Extract Profile_ID and Old_profile_name from the JSON string
                                profile_id=$(echo "$line" | jq -r '.Profile_ID')
                                old_profile_name=$(echo "$line" | jq -r '.Old_profile_name')
                                wlan_name_fromjosnfile=$(echo "$line" | jq -r '.wlan_list')
                                event_fromjsonfile=$(echo "$line" | jq -r '.Event')

                                ### Compare Profile_ID with get_profile_id
                                if [ "$profile_id" = "$get_profile_id" ]; then
                                    ### Replace Old_profile_name if Profile_ID matches
                                                json_string="$1"
                                                ### Main script starts here
                                                echo "$json_string"
                                                json_string="{\"wlan\":\"$wlan_name_fromjosnfile\",\"WifiCalling\":\"$event_fromjsonfile\",\"profile_id\":\"$get_profile_id\",\"RevisionNo\":\"$revisiono_new\"}"
                                                wlan_list=$(extract_json_field "$json_string" 'wlan')
                                                action=$(extract_json_field "$json_string" 'WifiCalling')
                                                profile_id=$(extract_json_field "$json_string" 'profile_id')
                                                Revision_No=$(extract_json_field "$json_string" 'RevisionNo')

                                                [ "$Revision_No" -gt '0' ] && echo "$Revision_No" > /etc/RevisionNo

                                                sed -i "/\"wlan_list\":\"$wlan_list\"/d" "$wifi_calling_saved_json"
                                                deconfigure_iptables_tc     ###function-call
                                                output_file="$wifi_calling_saved_json"

                                                for wlan_value in $(echo "$wlan_list" | tr ',' ' '); do
                                                wlan_interfaces=$(get_wlan_interfaces_json "$wlan_value")
                                                interfaces=$(echo "$wlan_interfaces" | jq -r '.interfaces')
                                                api_request="{\"id\":\"$profile_id\"}"
                                                api_response=$(fireapi -a /api/v1/get_wifi_calling_profile_data -d "$api_request" -j)

                                                for ssid_interface in $(echo "$interfaces" | tr ',' ' '); do
                                                while iptables -t mangle -L PREROUTING | grep -q EPDG_VOIP-CHAIN || iptables -t mangle -L POSTROUTING | grep -q EPDG_VOIP-CHAIN;
                                                do iptables -t mangle -D PREROUTING -p all -j EPDG_VOIP-CHAIN && iptables -t mangle -D POSTROUTING -p all -j EPDG_VOIP-CHAIN;
                                                done
                                                output=$(echo "$api_response" | jq -c -r --arg action_main "$action" --arg wlan_value "$wlan_value" --arg interface "$ssid_interface" --arg revision_no "$Revision_No" --arg profile_id "$profile_id" '
                                                        .data.Profile_Name as $profile |
                                                        .data.DataArray[] |
                                                        {
                                                            "Event": $action_main,
                                                            "Old_profile_name": $profile,
                                                            "MNC": .MNC,
                                                            "MCC": .MCC,
                                                            "dscp": .QosPriority,
                                                            "wlan_list": $wlan_value,
                                                            "ssid_interface": $interface,
                                                            "Revision_No": $revision_no,
                                                            "Profile_ID": $profile_id
                                                        } | @json'
                                                )
                                                echo "$output" >> "$output_file"
                                                function_roundoff       ###function-call
                                                unique      ###function-call
                                                todo        ###function-call
                                                unique      ###function-call
                                                done
                                               done
                                            else
                                        echo "$line" >> "$temp_file"    ### Print the original line if no match
                                    fi
                                done < "$wifi_calling_saved_json"
                                    deconfigure_iptables_tc       ###function-call
                                    cleanup_config_rules            ###function-call
                                    cleanup_previous_rules          ###function-call
                                    function_roundoff           ###function-call
                                    unique              ###function-call
                                    todo            ###function-call
                                    unique      ###function-call
                                    sh -x "$wifi_calling_saved_rules"
                            echo "LOGIC-HERE"
                            exit 1  ### Exit with failure as no match was found
                         else
                            echo "succesfully edited"
                        fi
            #########################################################################################################################################################################################

            ######################################################
            ###CHECK FOR NF TABLE CONDITION
            ######################################################
            ### Check if the file is present
            if [ -f /usr/lib/lua/luci/ap/update_nf_call.sh ]; then
                ### If the file is present, run the script
                sh /usr/lib/lua/luci/ap/update_nf_call.sh
            else
                echo "/usr/lib/lua/luci/ap/update_nf_call.sh not found,make sure it is available for nftable set to 1/0 to allow traffic flow in iptables" | tee -a "$log_save"
            fi
            ######################################################
    echo "Running epdg_voip.sh"s
    ### Release the lock
    rm -f "$LOCK_FILE"
    trap - INT TERM EXIT
else
    echo "Script is already running in background, exiting."
    exit 1
fi
###########################
###///END_OF_FILE