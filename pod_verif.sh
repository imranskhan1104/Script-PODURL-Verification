#!/bin/bash

start_time=$(date +%s.%N)

input_dir="test/"
output_dir="file_extract/"
qpapodList="cs-sensor/unix/Client/build/qpapods.txt"
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

if docker ps -a --format "{{.Names}}" | grep -q "qualys-container-sensor"; then
    docker stop qualys-container-sensor > /dev/null 2>&1
fi

for input_file in "$input_dir"/*.rpm; do

  if [ ! -f "$input_file" ]; then
    continue
  fi

  filename=$(basename "$input_file")

  echo "Extracting $filename to $output_dir ..." >> $report

  rpm2cpio "$input_file" | cpio -idmv -D "$output_dir"> /dev/null 2>&1

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

  pod=$(echo "$file" | sed -n 's/.*Sensor-\(.*\)-v1.*/\1/p')

  if [ -z "$pod" ]; then
      echo "Error: Failed to get pod name from RPM file" >> $report
      continue
  fi

  echo "POD: $pod" >> $report

  echo "------------------------------------------" >> $report

  tar -xvf "$file" -C "$output_dir" > /dev/null 2>&1

  if [ $? -ne 0 ]; then
      echo "Error: Failed to extract $file" >> $report
      continue
  fi

  echo "Extraction complete." >> $report

  if [ ! -d "/storage" ]; then
    mkdir /storage
  fi

  container_id=$(echo "$(sudo $output_dir/./installsensor.sh ActivationId=5cb7be7c-17da-470e-997e-cb417bc537d3 CustomerId=3eba8c3a-d968-53f6-8256-116e756841b7 Storage=/storage -s)" | sed -n 's/.*container ID: \([^ ]*\) successfully\./\1/p')

  if [ -z "$container_id" ]; then
    echo "Error: No running container found."
    continue
  fi

  podURL=$(echo "$(docker exec -it "$container_id" sh -c "cd /usr/local/qualys/qpa && sqlite3 Default_Config.db 'SELECT value FROM Settings WHERE \`Group\` = 2 and Item = 1;'")" | tr -dc '[:print:]' | tr -s ' ')

  value=$(grep -oP "(?<=${pod}=)[^[:space:]]+" "$qpapodList")

  qpapodURL=$(echo "$(echo "$value" | sed 's/|-\s*//')" | tr -dc '[:print:]' | tr -s ' ')

  if [ -z "$qpapodURL" ]; then
      echo "Error: Failed to get QPAPOD URL for from RPM file" >> $report
      continue
  fi

  if [ "$podURL" = "$qpapodURL" ]; then
    echo "Success: The URL for $pod is correct." >> $report
  else
    echo "Error: The URL for $pod is wrong." >> $report
  fi

  docker stop $container_id > /dev/null 2>&1

  docker rm -f $container_id > /dev/null 2>&1

  docker rmi -f $(cat $output_dir/image-id) > /dev/null 2>&1

  rm -rf $output_dir/*

  rm -rf /storage

  echo  >> $report

done

rm -rf $output_dir

end_time=$(date +%s.%N)

rounded_elapsed_time=$(printf "%.0f" "$(echo "$end_time - $start_time" | bc)")

echo "POD URL verification completed in  $rounded_elapsed_time seconds." >> $report

if [ -f "$report" ]; then
  cat "$report"
else
  echo "No RPM files found"
fi