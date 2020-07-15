#!/bin/bash
#set -e

CONFIG_PATH=/data/options.json

export MQTTIP=$(jq --raw-output ".MQTT_server" $CONFIG_PATH) #"$(bashio::config 'MQTT_server')"
export MQTTPORT=$(jq --raw-output ".MQTT_port" $CONFIG_PATH) #"$(bashio::config 'MQTT_port')"
export MQTTUSER=$(jq --raw-output ".MQTT_user" $CONFIG_PATH) #"$(bashio::config 'MQTT_user')"
export MQTTPASS=$(jq --raw-output ".MQTT_password" $CONFIG_PATH) #"$(bashio::config 'MQTT_password')"
export SCREENLOGICIP=$(jq --raw-output ".ScreenLogic_server" $CONFIG_PATH) #"$(bashio::config 'ScreenLogic_server')"
export POOLCIRCUIT=$(jq --raw-output ".pool_circuit" $CONFIG_PATH) #"$(bashio::config 'pool_circuit')"
export SPACIRCUIT=$(jq --raw-output ".spa_circuit" $CONFIG_PATH) #"$(bashio::config 'spa_circuit')"
export POOLLIGHTCIRCUIT=$(jq --raw-output ".pool_light_circuit" $CONFIG_PATH) #"$(bashio::config 'pool_light_circuit')"
export SPALIGHTCIRCUIT=$(jq --raw-output ".spa_light_circuit" $CONFIG_PATH) #"$(bashio::config 'spa_light_circuit')"
export JETSCIRCUIT=$(jq --raw-output ".jets_circuit" $CONFIG_PATH) #"$(bashio::config 'jets_circuit')"
export CLEANERCIRCUIT=$(jq --raw-output ".cleaner_circuit" $CONFIG_PATH) #"$(bashio::config 'cleaner_circuit')"

declare -A MESSAGELOOKUP
MESSAGELOOKUP=( ["ON"]="1" ["OFF"]="0" ["spa"]="1" ["pool"]="0" ["heat"]="1")

cd /node_modules/node-screenlogic

node initialize.js

while [ 1 ]; do
# change IP address (-h) port (-p) username (-u) and password (-P) to match your MQTT broker settings
PAYLOAD=`mosquitto_sub -h $MQTTIP -p $MQTTPORT -u $MQTTUSER -P $MQTTPASS -v -t pentair/# -W 10 -C 1`
if [ $? -gt 0 ]; then
  echo "MQTT Client exited with non-zero status"
  sleep 10
else
  echo "$PAYLOAD"
  TOPIC=`echo $PAYLOAD | awk '{print $1}'`
  MESSAGE=`echo $PAYLOAD | awk '{print $2}'`
  IFS="/"
  read -ra TOPICPARTS <<< $TOPIC

  TOPICROOT=$TOPICPARTS[0]

  if [ TOPICROOT == "pentair" ]; then

    TOPICACTION=$TOPICPARTS[1]

    case $TOPICACTION in
      "circuit")
      CIRCUITNUMBER=$TOPICPARTS[2]
      CIRCUITACTION=$TOPICPARTS[3]
      CIRCUITCOMMAND=$MESSAGELOOKUP[$MESSAGE]
      if [ CIRCUITACTION == "command" ]; then
        echo "set_circuit $CIRCUITNUMBER $CIRCUITCOMMAND"
        ./set_circuit $CIRCUITNUMBER $CIRCUITCOMMAND
      fi
    ;;
      "heater")
      POOLSYSTEM=$MESSAGELOOKUP[$TOPICPARTS[2]]
      HEATERACTION=$TOPICPARTS[3]
      HEATERCOMMAND=$TOPICPARTS[4]
      if [ HEATERACTION == "mode" && HEATERCOMMAND == "set" ]; then
        HEATERMESSAGE=$MESSAGELOOKUP[$MESSAGE]
        echo "set_heater $POOLSYSTEM $HEATERMESSAGE"
        ./set_heater $POOLSYSTEM $HEATERMESSAGE
      fi
      if [ HEATERACTION == "temperature" && HEATERCOMMAND == "set" ]; then
        echo "set_temp $POOLSYSTEM $MESSAGE"
        ./set_temp $POOLSYSTEM "$MESSAGE"
      fi
    ;;
    "light")
      LIGHTACTION=$TOPICPARTS[2]
      if [ LIGHTACTION == "command" ]; then
        echo "set_light $MESSAGE"
        ./set_light "${MESSAGE}"
      fi
    esac

fi

# change IP address (-h) port (-p) username (-u) and password (-P) to match your MQTT broker settings
node send_state_to_ha.js | awk -F, '{print "mosquitto_pub -h '"$MQTTIP"' -p '"$MQTTPORT"' -u '"$MQTTUSER"' -P '"$MQTTPASS"' -t " $1 " -m " $2}' | bash -s

done