#!/bin/env bash
source ~/.bashrc
while [[ "$(which chia)" == "" ]]; do
  . /opt/chia-blockchain/activate
done

source /root/.worker/env

apiKey=$APIKEY
baseUrl=$BASEURL
maxplot=5
plotter=$PLOTTER
core=$CORE
temp1="/temp1"
temp2="/temp2"
plotdir="/plots"
mount_chunk=/mount_chunk
log_path="/worker/plot_log"
#get cpu core count

if [[ -z $core ]]; then
  core=$(nproc)
fi

if [[ ! -d $log_path ]]; then
  mkdir -p $log_path
fi

farmer_Public_key=$(curl "$baseUrl/user?apiKey=$apiKey" | jq -r '.userInfo.farmerPublicKey')
contract_address=$(curl "$baseUrl/user?apiKey=$apiKey" | jq -r '.userInfo.contractAddress')

function validate_plot() {
  filepath=$1
  plotsize=$(ls -l $filepath | awk '{print $5}')
  if [[ $plotsize -lt 108000000000 ]]; then
    rm -rf $filepath
    return 1
  elif [[ $plotsize -gt 108000000000 ]]; then
    return 0
  fi
}
while true; do
  plotexistonplotdir=$(ls $plotdir -1 | grep ".plot$" | wc -l | xargs)
  plotexistonchunk=$(rclone ls $mount_chunk | grep ".plot$" | wc -l | xargs)
  declare -i maxplot=$maxplot
  declare -i plotexistonplotdir=$plotexistonplotdir
  declare -i plotexistonchunk=$plotexistonchunk

  if [[ $(($plotexistonplotdir + $plotexistonchunk)) -lt $maxplot ]]; then
    echo "[ $(date "+%H:%M:%S") ] Start Plotting"
    clear_ram
    rm -rf $temp1/*
    if [ ! -z $temp2 ]; then
      rm -rf $temp2/*
    fi
    rm -rf $plotdir/*.tmp
    if [[ $plotter == "madmax" ]]; then
      plottercmd="chia plotters madmax -r $core -n 1 -f $farmer_Public_key -c $contract_address -d $plotdir/ -t $temp1/"
      #if variable temp2 is set, add temp2 to plotter command inline
      if [ ! -z $temp2 ]; then
        plottercmd="$plottercmd -2 $temp2/"
      fi
    elif [[ $plotter == "bladebit_disk" ]]; then
      plottercmd="chia plotters bladebit diskplot -t $core -f $farmer_Public_key -c $contract_address -t $temp1/ $plotdir/ --cache ${bladebit_cache_size}G"
      if [ ! -z $temp2 ]; then
        plottercmd="$plottercmd -2 $temp2/"
      fi
    elif [[ $plotter == "bladebit" ]]; then
      plottercmd="chia plotters bladebit ramplot -r $core -f $farmer_Public_key -c $contract_address -d $plotdir/"
    fi
  else
    echo "[ $(date "+%H:%M:%S") ] Plotting Limit Reached"
    sleep 120
    continue
  fi
  echo $plottercmd
  plotlog="${log_path}/plot.log"
  echo "" >$plotlog
  $plottercmd | tee -a $plotlog

  if [[ $? -ne 0 ]]; then
    echo "[ $(date "+%H:%M:%S") ] Plot Failed"
    sleep 10
    continue
  fi

  echo "plotting selesai"

  if [[ $plotter == "madmax" ]]; then
    greplog=$(cat $plotlog | grep "copy to")
    plot_name=$(echo $greplog | grep -oE "[a-zA-Z0-9-]*\.plot")
    total=$(cat $plotlog | grep "Total plot creation")
    plottime=$(echo $total | cut -d " " -f6 | cut -d "." -f1)
  elif [[ $plotter == "bladebit_disk" ]]; then
    greplog=$(cat $plotlog | grep "Renaming plot to")
    plot_name=$(echo $greplog | grep -oE "[a-zA-Z0-9-]*\.plot")
    total=$(cat $plotlog | grep "Finished plotting")
    plottime=$(echo $total | cut -d " " -f4 | cut -d "." -f1)
  elif [[ $plotter == "bladebit" ]]; then
    greplog=$(cat $plotlog | grep "Renaming plot to")
    plot_name=$(echo $greplog | grep -oE "[a-zA-Z0-9-]*\.plot")
    total=$(cat $plotlog | grep "Finished plotting")
    plottime=$(echo $total | cut -d " " -f4 | cut -d "." -f1)
  fi

  if [[ -z $greplog ]]; then
    echo "[ $(date "+%H:%M:%S") ] Plot Failed"
    sleep 10
    continue
  fi
  filepath="${plotdir}/$plot_name"

  check_plot=$(validate_plot $filepath)
  result=$?
  if [[ $result -eq 1 ]]; then
    echo "[ $(date "+%H:%M:%S") ] Plot Failed"
    sleep 10
    continue
  fi

  filepath="${plotdir}/$plot_name"
  plot_size=$(rclone ls $filepath | awk '{print $1}')
  plot_id=$(echo $plot_name | cut -d "-" -f8 | cut -d "." -f1)

  echo "filepat=$filepath"
  echo "plot_size=$plot_size"
  echo "plot_id=$plot_id"

  #screen -dmS proses_${plot_id} upload_chunk $filepath

done
