#!/bin/env bash
source ~/.bashrc

while [[ "$(which chia)" == "" ]]; do
  . /opt/chia-blockchain/activate
done

source /root/.worker/env

baseUrl=$BASEURL
apiKey=$APIKEY
chunkPath=/mount_chunk
realPath=/chunk
plotsDir=/plots

while true; do
  chunkPath=/mount_chunk
  realPath=/chunk
  plotsDir=/plots
  SECONDS=0
  plotFile=$(rclone lsjson $chunkPath | jq '[.[] | select(.Name | endswith(".plot"))]')
  if [[ $plotFile == "[]" ]]; then
    plotFile=$(rclone lsjson $plotsDir | jq '[.[] | select(.Name | endswith(".plot"))]')
    if [[ $plotFile == "[]" ]]; then
      echo "no plot file found"
      sleep 60
      continue
    fi
    plotFile=$(echo $plotFile | jq -r --argjson plotSize 108000000000 '[ .[] | select(.Size > $plotSize) ] | sort_by(.ModTime) | first | .Name')
    if [[ -z $plotFile ]]; then
      echo "no plot file found"
      sleep 60
      continue
    fi
    rclone move $plotsDir/${plotFile} ${chunkPath} --ignore-checksum --progress
  else
    plotFile=$(echo $plotFile | jq -r --argjson plotSize 108000000000 '[ .[] | select(.Size > $plotSize) ] | sort_by(.ModTime) | first | .Name')
    if [[ -z $plotFile ]]; then
      echo "no plot file found"
      sleep 60
      continue
    fi
  fi

  plotDetail=$(rclone lsjson ${chunkPath}/${plotFile})
  if [[ $? -ne 0 ]]; then
    echo "file ${chunkPath}/${plotFile} not found"
    continue
  fi
  echo "file ${chunkPath}/${plotFile} found"
  plotName=$(echo $plotDetail | jq -r '.[0].Name')
  declare -i plotSize=$(echo $plotDetail | jq -r '.[0].Size')

  if [[ $plotSize -lt 108000000000 ]]; then
    echo "file ${chunkPath}/${plotFile} size is less than 108000000000 Byte"
    continue
  fi

  chunkDetail=$(rclone lsjson ${realPath} --include "${plotName}*")
  chunkCount=$(echo $chunkDetail | jq length)
  if [[ $chunkCount -eq 6 ]]; then
    chunkHead=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith(".plot")) | .Name')
    chunk001=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.001")) | .Name')
    chunk002=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.002")) | .Name')
    chunk003=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.003")) | .Name')
    chunk004=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.004")) | .Name')
    chunk005=$(echo $chunkDetail | jq -r '.[] | select(.Name | endswith("rclone_chunk.005")) | .Name')
    #check if all chunk variable is exist
    if [[ -z $chunkHead || -z $chunk001 || -z $chunk002 || -z $chunk003 || -z $chunk004 || -z $chunk005 ]]; then
      echo "file $plot_name | chunk file not found"
      #rclone delete $local_chunk_profile: --include ${plot_name}*
      continue
    fi
    echo "file ${chunkPath}/${plotFile} valid plot file has 6 chunk"

    chunkHeadSize=$(echo $chunkDetail | jq -r --arg chunkHead "$chunkHead" '.[] | select(.Name == $chunkHead) | .Size')
    chunk001Size=$(echo $chunkDetail | jq -r --arg chunk01 "$chunk001" '.[] | select(.Name == $chunk01) | .Size')
    chunk002Size=$(echo $chunkDetail | jq -r --arg chunk02 "$chunk002" '.[] | select(.Name == $chunk02) | .Size')
    chunk003Size=$(echo $chunkDetail | jq -r --arg chunk03 "$chunk003" '.[] | select(.Name == $chunk03) | .Size')
    chunk004Size=$(echo $chunkDetail | jq -r --arg chunk04 "$chunk004" '.[] | select(.Name == $chunk04) | .Size')
    chunk005Size=$(echo $chunkDetail | jq -r --arg chunk05 "$chunk005" '.[] | select(.Name == $chunk05) | .Size')
    totalChunkSize=$(($chunk001Size + $chunk002Size + $chunk003Size + $chunk004Size + $chunk005Size))
  else
    echo "file $plot_name | chunk file not found"
    #rclone delete $local_chunk_profile: --include ${plot_name}*
    continue
  fi

  if [[ $totalChunkSize -ne $plotSize ]]; then
    echo "file ${chunkPath}/${plotFile} size is not equal to chunk size"
    continue
  fi
  echo "file ${chunkPath}/${plotFile} valid plot file has 6 chunk and total chunk size is equal to plot size"
  #get FarmerPublicKey and ContractAddress
  /chia-blockchain/venv/bin/chia plots check -n 0 -g ${plotFile} >/dev/null 2>/tmp/${plotFile}.txt
  sleep 5
  farmerPublicKey=$(cat -v /tmp/${plotFile}.txt | grep "Farmer public key:" | rev | cut -d ":" -f1 | xargs | rev | cut -d "^" -f1 | xargs)
  contractAddress=$(cat -v /tmp/${plotFile}.txt | grep "Pool contract address:" | rev | cut -d ":" -f1 | xargs | rev | cut -d "^" -f1 | xargs)
  workerIpAddress=$(curl ipinfo.io/ip)
  chunkData=$(
    cat <<EOF
{
  "plotName": "${plotName}",
  "plotSize": ${plotSize},
  "contractAddress": "${contractAddress}",
  "farmerPublicKey": "${farmerPublicKey}",
  "workerIpAddress" : "${workerIpAddress}",
  "chunks":[
  {"type":"head","name":"${chunkHead}","size":${chunkHeadSize}},
  {"type":"chunk001","name":"${chunk001}","size":${chunk001Size}},
  {"type":"chunk002","name":"${chunk002}","size":${chunk002Size}},
  {"type":"chunk003","name":"${chunk003}","size":${chunk003Size}},
  {"type":"chunk004","name":"${chunk004}","size":${chunk004Size}},
  {"type":"chunk005","name":"${chunk005}","size":${chunk005Size}}
  ]}
EOF
  )
  while true; do
    registerChunk=$(
      curl --location "${baseUrl}/chunk/register?apiKey=${apiKey}" --request POST -H 'Content-Type: application/json' --data "${chunkData}"
    )
    success=$(echo $registerChunk | jq -r '.success')
    if [[ $success == "true" ]]; then
      break
    fi
    echo "register chunk failed, retry in 10 seconds"
    message=$(echo $registerChunk | jq -r '.message')
    echo "message: ${message}"
    sleep 10
  done
  chunkId=$(echo $registerChunk | jq -r '.results.id')
  chunkArray=(head chunk001 chunk002 chunk003 chunk004 chunk005)

  echo "submit chunk to storj with chunkId ${chunkId}"

  uploadStorj() {
    local chunk=$1
    local chunkData=$2
    local baseUrl=$3
    local apiKey=$4
    local fileType=$(echo $chunkData | jq -r '.chunks[] | select(.type == "'$chunk'") | .type')
    if [[ "$fileType" == "head" ]]; then
      echo "uploading ${chunk} to storj skipping"
      sleep 3
      return 0
    fi
    local fileName=$(echo $chunkData | jq -r '.chunks[] | select(.type == "'$chunk'") | .name')
    local fileSize=$(echo $chunkData | jq -r '.chunks[] | select(.type == "'$chunk'") | .size')
    local plotName=$(echo $chunkData | jq -r '.plotName')
    while true; do
      while true; do
        storj=$(curl -s -X GET --location "${baseUrl}/storj/getOne?apiKey=${apiKey}")
        if [[ $(echo $storj | jq '.success') == "true" ]]; then
          break
        fi
        curl -s -X GET --location "${baseUrl}/chunk/refresh?apiKey=${apiKey}?chunkId=${chunkId}"
        sleep 60
      done
      storjId=$(echo $storj | jq -r '.results.id')
      accessGrant=$(echo $storj | jq -r '.results.accessGrant')
      export RCLONE_CONFIG_${storjId^^}_TYPE=storj
      export RCLONE_CONFIG_${storjId^^}_ACCESS_GRANT=${accessGrant}
      export RCLONE_CONFIG_${storjId^^}CRYPT_TYPE=crypt
      export RCLONE_CONFIG_${storjId^^}CRYPT_REMOTE=${storjId}:
      export RCLONE_CONFIG_${storjId^^}CRYPT_DIRECTORY_NAME_ENCRYPTION=false
      export RCLONE_CONFIG_${storjId^^}CRYPT_PASSWORD=ZEOxWBrSqHDgX59iE9DF3XVFVP8
      randFile=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
      randSize=$(shuf -i 100-200 -n 1)
      randSize2=$(shuf -i 100-200 -n 1)
      fallocate -l ${randSize}K /tmp/${randFile}
      fallocate -l ${randSize2}K /tmp/${randFile}_2
      #killall gateway
      randMd5=$(md5sum /tmp/${randFile} | awk '{print $1}')
      randMd52=$(md5sum /tmp/${randFile}_2 | awk '{print $1}')
      #ACCESSGRANT=${accessGrant} yq -i '.access = strenv(ACCESSGRANT)' ~/.local/share/storj/gateway/config.yaml
      #gateway run >/dev/null 2>&1 &
      #gatewayPid=$!
      sleep 3
      rclone copy /tmp/${randFile} ${storjId}CRYPT:demo-bucket
      rclone copy /tmp/${randFile}_2 ${storjId}CRYPT:demo-bucket
      tempOnStorj=$(rclone lsjson ${storjId}CRYPT:demo-bucket --include ${randFile})
      tempOnStorj2=$(rclone lsjson ${storjId}CRYPT:demo-bucket --include ${randFile}_2)
      if [[ $(echo $tempOnStorj | jq '. | length') -eq 0 ]]; then
        echo "file ${randFile} not found"
        curl -X POST --location "${baseUrl}/storj/updateStorj?apiKey=${apiKey}&storjId=${storjId}&status=error"
        continue
      fi
      if [[ $(echo $tempOnStorj2 | jq '. | length') -eq 0 ]]; then
        echo "file ${randFile}_2 not found"
        curl -X POST --location "${baseUrl}/storj/updateStorj?apiKey=${apiKey}&storjId=${storjId}&status=error"
        continue
      fi
      rclone delete ${storjId}CRYPT:demo-bucket --include ${randFile}
      rclone delete ${storjId}CRYPT:demo-bucket --include ${randFile}_2
      sleep 3
      listBucket=$(rclone lsd ${storjId^^}:)
      buckets=()

      while IFS= read -r line; do
        # Extract the directory name from each line
        bucket=$(echo "$line" | awk '{print $NF}')

        # Add the directory name to the array
        buckets+=("$bucket")
      done <<<"$listBucket"

      for bucket in "${buckets[@]}"; do
        rclone delete ${storjId^^}CRYPT:${bucket}
      done
      rclone mkdir ${storjId^^}CRYPT:demo-bucket
      rclone move ${realPath}/${fileName} ${storjId}CRYPT:demo-bucket --s3-disable-checksum --progress
      if [[ $? -ne 0 ]]; then
        echo "upload ${fileName} to storj failed"
        unset RCLONE_CONFIG_${storjId^^}_TYPE
        unset RCLONE_CONFIG_${storjId^^}_ACCESS_GRANT
        unset RCLONE_CONFIG_${storjId^^}CRYPT_TYPE
        unset RCLONE_CONFIG_${storjId^^}CRYPT_REMOTE
        unset RCLONE_CONFIG_${storjId^^}CRYPT_DIRECTORY_NAME_ENCRYPTION
        unset RCLONE_CONFIG_${storjId^^}CRYPT_PASSWORD
        rm -rf /tmp/${randFile}
        curl -X POST --location "${baseUrl}/storj/updateStorj?apiKey=${apiKey}&storjId=${storjId}&status=error"
        #make sure source file still exist
        if [[ ! -f ${realPath}/${fileName} ]]; then
          echo "file ${realPath}/${fileName} not found"
          curl -X POST --location "${baseUrl}/storj/updateStorj?apiKey=${apiKey}&storjId=${storjId}&status=error"
          return 1
        fi
        continue
      fi
      #make sure file exist on storj
      chunkOnStorj=$(rclone lsjson ${storjId}CRYPT:demo-bucket --include ${fileName})
      if [[ $(echo $chunkOnStorj | jq '. | length') -eq 0 ]]; then
        echo "file ${fileName} not found"
        curl -X POST --location "${baseUrl}/storj/updateStorj?apiKey=${apiKey}&storjId=${storjId}&status=error"
        return 1
      fi
      curl -X POST --location "${baseUrl}/chunk/updateChunkLocation?apiKey=${apiKey}&storjId=${storjId}&chunkId=${chunkId}&partType=${fileType}&status=filled"

      echo "upload ${fileName} to storj done"
      if [[ "$fileType" == "chunk001" ]]; then
        rclone move ${realPath}/${plotName} ${storjId}CRYPT:demo-bucket --s3-disable-checksum --progress
        if [[ $? -eq 0 ]]; then
          curl -X POST --location "${baseUrl}/chunk/updateChunkLocation?apiKey=${apiKey}&storjId=${storjId}&chunkId=${chunkId}&partType=head&status=filled"
          echo "upload ${fileName} head to storj done"
        fi
      fi
      #killall gateway
      sleep 3
      unset RCLONE_CONFIG_${storjId^^}_TYPE
      unset RCLONE_CONFIG_${storjId^^}_ACCESS_GRANT
      unset RCLONE_CONFIG_${storjId^^}CRYPT_TYPE
      unset RCLONE_CONFIG_${storjId^^}CRYPT_REMOTE
      unset RCLONE_CONFIG_${storjId^^}CRYPT_DIRECTORY_NAME_ENCRYPTION
      unset RCLONE_CONFIG_${storjId^^}CRYPT_PASSWORD
      rm -rf /tmp/${randFile}
      rm -rf /tmp/${randFile}_2

      break
    done
  }

  processArray=()
  for chunk in "${chunkArray[@]}"; do
    echo "uploading ${chunk} to storj"
    uploadStorj $chunk "$(echo -n "$chunkData")" $baseUrl $apiKey &
    processId=$!
    processArray+=($processId)
    sleep 5
  done

  for pid in ${processArray[@]}; do
    wait $pid
  done

  chunkConfig=$(curl -X GET --location "${baseUrl}/chunk/genConfig?apiKey=${apiKey}&chunkId=${chunkId}")
  chunkConfig=$(echo $chunkConfig | jq '.results')
  echo -e $chunkConfig >~/.config/${chunkId}.conf
  #remove '"' from config file
  sed -i 's/"//g' ~/.config/${chunkId}.conf
  chunkCheck=$(rclone lsjson ${chunkId}: --config ~/.config/${chunkId}.conf)
  if [[ $? -ne 0 ]]; then
    echo "chunk ${chunkId} not found"
    curl -X POST --location "${baseUrl}/chunk/updateChunkStatus?apiKey=${apiKey}&chunkId=${chunkId}&status=error"
    continue
  fi
  #check if plot file exist in chunk
  plotOnChunk=$(echo $chunkCheck | jq -r '.[] | select(.Name | endswith(".plot")) | .Name')
  if [[ -z $plotOnChunk ]]; then
    echo "plot file not found in chunk ${chunkId}"
    curl -X POST --location "${baseUrl}/chunk/updateChunkStatus?apiKey=${apiKey}&chunkId=${chunkId}&status=error"
    continue
  fi
  #check if plotOnChunk match plotFile
  if [[ $plotOnChunk != $plotName ]]; then
    echo "plot file not match in chunk ${chunkId}"
    curl -X POST --location "${baseUrl}/chunk/updateChunkStatus?apiKey=${apiKey}&chunkId=${chunkId}&status=error"
    continue
  fi
  #check if chunk size is equal to plot size
  plotSizeOnChunk=$(echo $chunkCheck | jq -r '.[] | select(.Name | endswith(".plot")) | .Size')
  if [[ $plotSizeOnChunk -ne $plotSize ]]; then
    echo "plot size not match in chunk ${chunkId}"
    #curl -X POST --location "${baseUrl}/chunk/updateChunkStatus?apiKey=${apiKey}&chunkId=${chunkId}&status=error"
    continue
  fi
  curl -X POST --location "${baseUrl}/chunk/updateChunkStatus?apiKey=${apiKey}&chunkId=${chunkId}&status=done"
  echo ""
  echo ""
  echo "total time: $SECONDS seconds"
  sleep 10
done
