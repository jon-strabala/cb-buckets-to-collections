#!/bin/bash

#
# Jon A. Strabala, data_load.sh
# Couchbase, Inc.
# Enjoy
#

echo 
echo "# This bash script, 'big_data_test_load.sh', will load <N> million test" 
echo "# documents into a <bucket>._default._default in 1 million chunks as" 
echo "# created by the perl script 'big_data_test_gen.pl'.  The data will"
echo "# have 80 different document type values evenly distributed."
echo 


which cbimport 2>&1 > /dev/null
if [ "$?" -eq "1" ] ; then
  echo "Please add the Couchbase binary 'cbimport' to your search PATH"
  exit
fi

which perl 2>&1 > /dev/null
if [ "$?" -eq "1" ] ; then
  echo "Please add the perl script interpreter to your search PATH"
  exit
fi

read -e -p "Enter the number of test docs to create in the millions     " -i "250" millions
read -e -p "Enter the bucket (or target) to load test docs into         " -i "input" bucket
read -e -p "Enter the username:password to your cluster                 " -i "admin:jtester" userpass
read -e -p "Enter the hostname or ip address of your cluster            " -i "localhost" clusterip
read -e -p "Enter the number of threads for cbimport                    " -i "8" threads

arry=(${userpass//:/ })
user=${arry[0]};
pass=${arry[1]};

echo
echo "Will load $millions million test docs into keyspace ${bucket}._default._default (the default for bucket ${bucket})"
echo "type ^C to abort, running in 5 sec."
sleep 5
echo "Running ...."
echo 

for ((i = 1 ; i <= $millions ; i++)); do
  echo -n "gen/cbimport block: $i of $millions, start at " ; date
  ./big_data_test_gen.pl --blk $i --num 1000000 > ./data.json
  cbimport json -c couchbase://$clusterip -u $user -p $pass -b input -d file://./data.json  -f lines -t $threads -g test::%id%
done


