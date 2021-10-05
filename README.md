# cb-buckets-to-collections
Tool (perl script) and template to convert bucket based data into collections

Example of performance using this technique:
* Test cluster a symmetric 3 x AWS r5.2xlarge (64 GiB of memory, 8 vCPUs, 64-bit platform) 
* Will process 93K ops/sec. in a steady state.
* 250M small documents: time 44 minutes to reorganize a bucket with 80 types into a new bucket with 80 collections.
* 1B small documents: time 3 hours to reorganize a bucket with 80 types into a new bucket with 80 collections.

Note a large cluster should be able to hit 1.1M ops/sec. refer to http://showfast.sc.couchbase.com/#/timeline/Linux/eventing/scaling/Function

## Example

Ii is assumed that you have a basic understanding of Couchbase Eventing and have the following environment:

* The `travel-sample` data set loaded in a Couchbase cluster with a version greater than or equal to 7.0.0
* The `perl` scripting utilities installed
* The JSON tool `jq` installed
* Your path includes `/opt/couchbase/bin` as well as the location for both `perl` and `jq`.

## Step 1:

Execute the generator script, this just makes two files.

```
./CustomConvertBucketToCollections.pl
```

The script just asks 8 or 9 then builds our Eventing Functions (plus a setup of script to make sure the target collections exist).

```
Enter the bucket (or source) to convert to collections      [travel-sample]:
Enter the username:password to your cluster                 [admin:jtester]:
Enter the hostname or ip address of your cluster            [localhost]:
Enter the destination bucket.scope                          [mybucket.myscope]:
Enter the Eventing storage keyspace bucket.scope.collection [rr100.eventing.metadata]:
Enter the number of workers (LTE # cores more is faster)    [8]:
Probe the bucket (or source) to determine the set of types  [Y]:
  samples across the bucket (or source) to find types       [20000]:
  maximum estimated # of types in the bucket (or source)    [30]:

Scanning travel-sample for 'type' property this may take a few seconds

curl -s -u admin:jtester http://localhost:8093/query/service -d \
    'statement=INFER `travel-sample`._default._default WITH {"sample_size": 20000, "num_sample_values": 30, "similarity_metric": 0.1}' | \
    jq '.results[][].properties.type.samples | .[]' | sort -u

TYPES FOUND: airline airport hotel landmark route

Generating Eventing Function: CustomConvertBucketToCollections.json

Generating Keyspace commands: MakeCustomKeyspaces.sh
```

Where there are two output files are :
* CustomConvertBucketToCollections.json
* MakeCustomKeyspaces.sh

The first file  _CustomConvertBucketToCollections.json_ is a complete Eventing Function which can be run to move your data from a bucket to a set of collections based on the property "type" this file can be imported into your Eventing Service in your Couchbase cluster.

The second file _MakeCustomKeyspaces.sh_ is a shell script that can be run to setup the Eventing Storage (or Eventing metadata) and also all the target collections.

## Step 2:

Inspect the setup script MakeCustomKeyspaces.sh

```
cat MakeCustomKeyspaces.sh
```
```
# SAMPLE: Eventing Storage

couchbase-cli bucket-create -c localhost:8091 -u admin -p jtester --bucket=rr100 --bucket-type=couchbase \
        --bucket-eviction-policy fullEviction --bucket-ramsize=100 --bucket-replica=0 --enable-flush=1 --wait
couchbase-cli collection-manage --create-scope eventing --bucket rr100 -u admin -p jtester -c localhost:8091
couchbase-cli collection-manage --create-collection eventing.metadata --bucket rr100 -u admin -p jtester -c localhost:8091

# SAMPLE: Target bucket.scope.collections

couchbase-cli bucket-create -c localhost:8091 -u admin -p jtester --bucket=mybucket --bucket-type=couchbase \
        --bucket-eviction-policy fullEviction --bucket-ramsize=100 --bucket-replica=0 --enable-flush=1 --wait
couchbase-cli collection-manage --create-scope myscope --bucket mybucket -u admin -p jtester -c localhost:8091
couchbase-cli collection-manage --create-collection myscope.airline --bucket mybucket -u admin -p jtester -c localhost:8091
couchbase-cli collection-manage --create-collection myscope.airport --bucket mybucket -u admin -p jtester -c localhost:8091
couchbase-cli collection-manage --create-collection myscope.hotel --bucket mybucket -u admin -p jtester -c localhost:8091
couchbase-cli collection-manage --create-collection myscope.landmark --bucket mybucket -u admin -p jtester -c localhost:8091
couchbase-cli collection-manage --create-collection myscope.route --bucket mybucket -u admin -p jtester -c localhost:8091

# IMPORT THE FUNCTION (must not exist)

couchbase-cli eventing-function-setup -c  localhost:8091 -u admin -p jtester \
        --import --name CustomConvertBucketToCollections --file CustomConvertBucketToCollections.json

```

## Step 3:

Adjust any needed settings in the setup script MakeCustomKeyspaces.sh - note my defaults will typically be different from a production environment.

```
vi MakeCustomKeyspaces.sh
```

## Step 4:

Execute the setup script MakeCustomKeyspaces.sh to make sure all the needed collections exist and import the Eventing Function CustomConvertBucketToCollections.json

```
sh ./MakeCustomKeyspaces.sh
```
## Step 5: 

Refresh your browser to see the Eventing Function "CustomConvertBucketToCollections" in the Couchbase server UI then view function settings, adjust the constant alias bindings (at the bottom of the pop-up). 

* DO_COPY 

If `true` will copy data from the source bucket to the target collection(s)

* DO_DELETE

If `true` will delete data from the source bucket

* DROP_TYPE

If `true` will remove the property "type" form the document copied to the target collection(s)

## Step 6: 

Deploy the Eventing Function "CustomConvertBucketToCollections" to perform the needed reorganization action(s).

Now Wait until it is complete (the rate graph if expanded should go to zero) then Undeploy the Function.

