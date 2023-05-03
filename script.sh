#!/bin/bash

start_time=$(date +%s.%N)

input_dir="rpm/"
output_dir="file_extract/"
config_file="$output_dir/cssensor-dcos.json"
qpapod="cs-sensor/unix/Client/build/qpappods.txt"
#log_file="script_log.txt"
report="test_report.log"

if [ -f "$report" ]; then
  rm "$report"
fi

if [ -d "$output_dir" ]; then
  rm -rf "$output_dir"
fi

mkdir -p "$output_dir"

if [ ! -d "$input_dir" ]; then
  echo "Error: Input directory not found: $input_dir" >> $report
  exit 1
fi

if [ ! -d "$output_dir" ]; then
  echo "Error: Output directory not found: $output_dir"  >> $report
  exit 1
fi

for input_file in "$input_dir"/*.rpm; do

  if [ ! -f "$input_file" ]; then
    continue
  fi

  filename=$(basename "$input_file")

  echo "Extracting $filename to $output_dir ..." >> $report

  rpm2cpio "$input_file" | cpio -idmv -D "$output_dir"> /dev/null 2>&1

#  mv "usr" "file_extract/"

  if [ $? -ne 0 ]; then
    echo "Error: RPM extraction failed for $filename"  >> $report
    continue
  fi

  mv "$output_dir/usr/local/qualys/cssensor/"* "$output_dir"

  file=$(find "$output_dir" -type f -name "QualysContainerSensor*")

  if [ -z "$file" ]; then
      echo "Error: Failed to get the file to extract" >> $report
      continue
  fi

#  echo "$file" >> $report

  pod=$(echo "$file" | sed -n 's/.*Sensor-\(.*\)-v1.*/\1/p')

  if [ -z "$pod" ]; then
      echo "Error: Failed to get pod name from RPM file" >> $report
      continue
  fi

  echo "POD: $pod" >> $report

  echo "------------------------------------------" >> $report

  tar -xvf "$file" -C "$output_dir" > /dev/null 2>&1

  tar -xvf "$output_dir/qualys-sensor.tar" -C "$output_dir" > /dev/null 2>&1

  if [ $? -ne 0 ]; then
      echo "Error: Failed to extract $file" >> $report
      continue
  fi

  echo "Extraction complete." >> $report

 jsonFile=$(ls $output_dir/*json)

  image_sources=()

  while IFS= read -r -d '' jsonFile; do
    if [[ -f "$jsonFile" && "${#jsonFile}" -gt 50 ]]; then
      imageJSON=$jsonFile
      sources=$(grep -o '"image-source": *"[^"]*"' "$imageJSON" | cut -d '"' -f 4)
      readarray -t sources_array <<< "$sources"
      for source in "${sources_array[@]}"; do
        image_sources+=("$source")
      done
    fi
  done < <(find "$output_dir" -name "*.json" -type f -print0)

  if [ ${#image_sources[@]} -gt 1 ]; then
    if [ "${image_sources[0]}" = "${image_sources[1]}" ]; then
      if [ "$pod" = "${image_sources[0]}" ]; then
        echo "Success: The URL for $pod is correct." >> $report
      else
        echo "Error: The URL for $pod is wrong." >> $report
      fi
    else
      echo "Error: The POD is not matching in Image JSON." >> $report
    fi
  else
    if [ "$pod" = "${image_sources[0]}" ]; then
        echo "Success: The URL for $pod is correct." >> $report
    else
        echo "Error: The URL for $pod is wrong." >> $report
    fi
  fi


#  pod_url=$(grep -oP '(?<="POD_URL": ")[^"]*' "$config_file")
#
#  if [ -z "$pod_url" ]; then
#      echo "Error: Failed to get POD_URL from $config_file" >> $report
#      continue
#  fi
#
##  echo "$pod_url" >> $report
#
#  value=$(grep -oP "(?<=${pod}=)[^[:space:]]+" "$qpapod")
#
#  qpapodURL=$(echo "$value" | sed 's/|-\s*//')
#
#  if [ -z "$qpapodURL" ]; then
#      echo "Error: Failed to get QPAPOD URL for from RPM file" >> $report
#      continue
#  fi
#
#
##  echo "$qpapodURL" >> $report
#
#  if [ "$pod_url" = "$qpapodURL" ]; then
#    echo "Success: The URL for $pod is correct." >> $report
#  else
#    echo "Error: The URL for $pod is wrong." >> $report
#  fi

  rm -rf $output_dir/*

  echo  >> $report

done

rm -rf $output_dir

end_time=$(date +%s.%N)

rounded_elapsed_time=$(printf "%.0f" "$(echo "$end_time - $start_time" | bc)")

echo "POD URL verification completed in  $rounded_elapsed_time seconds." >> $report

if [ -f "$report" ]; then
  cat "$report"
fi

