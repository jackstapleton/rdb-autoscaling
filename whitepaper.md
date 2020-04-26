# RDB Autoscaling

## Introduction

Cloud Computing has fast become the new normal.
It is easy to use, reliable, secure and most importantly cost effective.
Servers, storage and networking can be provisioned on demand, without the technical knowledge usually needed to set up these services.
The vast infrastructure of the big Cloud Platforms can be utilised to run servers and store data across multiple regions to secure their availability.
This Infrastructure-as-a-Service (IaaS) model can mean substantial reductions in IT infrastructure costs.

This model has been taken a step further with Auto Scaling technologies.
Now customers can scale their infrastructure to meet their system's demand without manual intervention.
This elasticity is one of the key benefits of Cloud Computing.
It means that systems can be scaled up quickly to meet demand without the complicated and time consuming process of provisioning new physical resources.

As these technologies develop it is important to start incorporating them into kdb+.
In this paper we will explore a solution for one of the most important Auto Scaling use cases in kdb+, Auto Scaling the Real-time Database.

## Auto Scaling

Auto Scaling is the act of monitoring the load on a system and dynamically acquiring or shutting down resources in order to match this load.
When planning a new project we no longer need to provision one large computing resource, whose capacity will need to forever meet its demand.
Instead we can use clusters of smaller resources and scale them in and out to follow demand.

### Auto Scaling and kdb+

With regard to kdb+ Auto Scaling has 4 main use cases.
- Storage capacity for data.
- Compute for reading.
- Compute for writing.
- Memory for caching.

Scaling storage can be relatively simple, the size or the number of storage volumes can be increased as the database grows.

Scaling compute for reading data has been covered by Rebecca Kelly in her blog post [Kx in the Public Cloud: Autoscaling using kdb+](https://kx.com/blog/kx-in-the-public-cloud-auto-scaling-using-kdb).
Here Rebecca demonstrates how to launch multiple servers which all load the same Historical Database (HDB) to scale the compute for historical queries.

Dynamically scaling the compute needed for writing can be a bit more complicated.
Given we want to maintain the data's order, the feed must all go through one point for a given data source.

The same can be said for scaling the memory needed in a Real-time Database.
In this case we must ensure that no data is duplicated across the cluster.
Solving this issue will be the objective of this paper.

### Auto Scaling the Reall-time Database (RDB)

By Auto Scaling the RDB we will improve both the Cost Efficiency and the Availability of our databases.

#### Why use Auto Scaling

Lets say on average we will receive 12GBs of data evenly throughout the day.
For a regular kdb+ system we will provision one server with 16GB of RAM, this will allow for some contingency capacity.
We then hope that the data volumes do not exceed that 16GB limit on a daily basis.

![Large RDB Server](/ref/img/ExampleRegularCapacity.png)
|---|
| Figure X: |

In a scalable cluster we can begin the day with one small server (for this example a quarter of the size, 4GB).
The RAM need to hold the real-time data in memory will grow throughout the day and we can then step up our capacity by launching more servers.

![ASG RDBs](/ref/img/ExampleASGCapacity.png)
|---|
| Figure X: |

#### Cost Efficiency

At the beginning of the day we will not be paying for the extra compute and memory of the large server.
The potential cost savings for this example are displayed below between the ASG's capacity and Large Server's.

![Cost Savings](/ref/img/ExampleASGCostEfficiency.png)
|---|
| Figure X: |

In the cloud **you pay only for what you use**.
Therefore, in a perfect system there should be no spare computing resources running idle accumulating costs.
By ensuring this we can maintain the performance of a system at the lowest possible cost.

It is worth noting that the amount of servers you provision has no real bearing on the overall cost.
I.e., you will pay the same for running one server with 16GBs of RAM as you would for four running servers with 4GBs.

Below is an example of Amazon Web Service's pricing for varying sizes of its t3a instances.
As you can see the price is largely proportional to the Memory of each instance.;

![T3 Prices](/ref/img/T3aEc2Pricing.png)
|---|
| Figure X: |


#### Availability

Most importantly replacing the large server with a scalable cluster will make our system more reliable.

With Auto Scaling we can stop guessing our capacity needs.
By dynamically acquiring resources we can ensure that the load on our system never exceeds its capacity.
This will safe guard against unexpected large spikes in data volumes crippling our system.

![ASG Availability](/ref/img/ExampleASGAvailability.png)
|---|
| Figure X: |

When developing a new application there is no need make the dangerous estimation of how much memory our RDBs will need throughout the systems life.
Even if the estimate turns out to be correct, we will still end up provisioning resources that will lie mostly idle.
Demand varies and so should our capacity.

Distributing the day's data among multiple smaller servers will also increase the system's resiliency.
One fault will no longer mean an entire system goes down and the smaller RDBs will only have to replay a portion of the Tickerplant's log reducing the time to recover.

## Amazon Web Services (AWS)

The Amazon Web Services (AWS) cloud platform was used for this paper, but the code should be transferable to others.
The AWS Resources used to deploy are described below.

### Amazon Machine Image (AMI)

As multiple servers will be launched, all needing kdb+ and code to scale the RDBs, the first step was to create an Amazon Machine Image.
An AMI is a template Amazon's Elastic Compute Cloud (EC2) uses to start instances.
Creating one with our code and software means we can start multiple EC2 instances with identical software, this will ensure consistency across our Stack.

To do this a regular EC2 instance was launched, kdb+ was installed, and our code was deployed to the server.
The Amazon Command Line Interface (CLI) was then used to create an image of the server.
This could also be done using the AWS Console.

```bash
aws ec2 create-image --instance-id i-1234567890abcdef --name kdb-rdb-autoscaling-ami-v1
```

Once available the AMI was used along with Cloudformation deploy a stack.

### Cloudformation

With AWS Cloudformation we can use a `yaml` file to provision AWS resources.
The resources needed in our stack are outlined below.
An example `yaml` file to deploy it can be found in Appendix 1.

- AWS Elastic File System (EFS).
- EC2 Launch Templates.
- Auto Scaling Groups.

#### AWS ElasticFileSystem (EFS)

EFS is a Network File System (NFS) which any EC2 instance can mount.
This solves the first problem we will face when putting the Tickerplant and RDB on different servers.
Without a common file system the RDB would not be able to replay the Tickerplant's log file to recover.

#### EC2 Launch Template

On AWS, Launch Templates can be used to configure details for an EC2 Instance ahead of time.
E.g., instance type, root volume size, AMI id.
Our Auto Scaling groups will use these templates to launch their servers.

### Auto Scaling Group (ASG)

Auto Scaling groups (ASG) can be used to maintain a number of instances in a cluster.
If any of the instances in the group become unhealthy the ASG will terminate it, and launch a new one in its place, maintaining the compute capacity of the group.

##### Recovery

The first Auto Scaling group we deploy will be for the Tickerplant.
Even though there will only ever be one instance for the Tickerplant we are still putting it in an ASG for recovery purposes.
If it goes down the ASG will automatically start another one.

##### Scalability

There are a number of ways an ASG can scale its instances on AWS.

- Scheduled
    * Set timeframes to scale in and out.
- Predictive
    * Machine learning is used to predict demand.
- Dynamic
    * Cloudwatch Metrics are monitored to follow the flow of demand.
    * E.g., CPU and Memory Usage.
- Manual
    * Adjusting the ASG's `DesiredCapacity` attribute.
    * Can be done through the console or the AWS CLI.

#### Manual Scaling

We could conceivably publish Cloudwatch Metrics for Memory Usage from our RDBs and allow AWS to manage scaling out.
If the memory across the cluster rises to a certain limit the ASG will increment its `DesiredCapacity` attribute and launch a new server.

Sending custom Cloudwatch Metrics is relatively simple using either python's boto3 library or the AWS CLI.
Examples of how to use these can be found in Appendix 2.

Another way to scale the instances in an ASG, and the method more suitable for our use case, is to manually adjust the ASG's `DeciredCapacity` attribute.
Or more specifically have the RDBs do it.
Managing the Auto Scaling within the application is preferable because we want to be specific when scaling in.

To scale in, AWS will choose which instance to terminate based on certain criteria.
E.g., instance count per Availability Zone, time to the next next billing hour.
You are able to replace the default behaviour with other options like `OldestInstance`, `NewestInstance` etc.
However, if all of the criteria have been evaluated and there are still multiple instances to choose from, AWS will pick one at random.

Under no circumstance do we want AWS to terminate an instance of an RDB process which is still holding today's data.
So we will need to keep control of the Auto Scaling group's `DesiredCapacity` within the application.

As with publishing Cloudwatch Metrics, adjusting the `DesiredCapacity` can be done with python's boto3 library or the AWS CLI.
Appendix 3 has examples of how to use these.

#### Auto Scaling in Q

As the AWS CLI simply uses unix commands we can run them in `Q` using `system`.
If we configure the CLI to return `json` we can then parse the output using `.j.k`.

```q
/ aws cli commands should be wrapped in a retry loop as they may timeout when aws is under load
.util.sys.runWithRetry:{[cmd]
    n: 0;
    while[not last res:.util.sys.runSafe cmd;
            system "sleep 1";
            if[10 < n+: 1; 'res 0];
            ];
    res 0
 };

.util.sys.runSafe: .Q.trp[{(system x;1b)};;{-1 x,"\n",.Q.sbt[y];(x;0b)}];

```

To adjust the `DesiredCapacity` of an ASG we first need to find the correct group.
To do this we will use the `aws ec2` functions to find the `AutoScalingGroupName` that the RDB server belongs to.

```q
/ aws ec2 cli commands
.util.aws.getInstanceId: {last " " vs first system "ec2-metadata -i"};

.util.aws.describeInstance:{[instanceId]
    res: .util.sys.runWithRetry "aws ec2 describe-instances --filters  \"Name=instance-id,Values=",instanceId,"\"";
    res: (.j.k "\n" sv res)`Reservations;
    if[() ~ res; 'instanceId," is not an instance"];
    flip first res`Instances
 };

.util.aws.getGroupName:{[instanceId]
    tags: .util.aws.describeInstance[instanceId]`Tags;
    res: first exec Value from raze[tags] where Key like "aws:autoscaling:groupName";
    if[() ~ res; 'instanceId," is not in an autoscaling group"];
    res
 };
```

To increment the capacity to scale up we can use the `aws autoscaling` to find the current `DesiredCapacity`.
Once we have this we can add one and adjust the attribute.
The ASG will then automatically launch a server.

```q
/ aws autoscaling cli commands
.util.aws.describeASG:{[groupName]
    res: .util.sys.runWithRetry "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name ",groupName;
    res: flip (.j.k "\n" sv res)`AutoScalingGroups;
    if[() ~ res; 'groupName," is not an autoscaling group"];
    res
 };

.util.aws.getDesiredCapacity:{[groupName]
    first .util.aws.describeASG[groupName]`DesiredCapacity
 };

.util.aws.setDesiredCapacity:{[groupName;n]
    .util.sys.runWithRetry "aws autoscaling set-desired-capacity --auto-scaling-group-name ",groupName," --desired-capacity ",string n
 };

.util.aws.scale:{[groupName]
    .util.aws.setDesiredCapacity[groupName] 1 + .util.aws.getDesiredCapacity groupName;
 };
```

To scale in the RDB will terminate its own server.
When doing this it must make the call to the ASG, it will then know not to launch a new instance in its place.

```q
.util.aws.terminate:{[instanceId]
    .j.k "\n" sv .util.sys.runWithRetry "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"
 };
```

Lastly, for monitoring purposes the function below can be used to publish Cloudwatch Metrics.

```q
/ aws cloudwatch put-metric-data
.util.aws.putMetricDataCW:{[namespace;dimensions;metric;unit;data]
    .util.sys.runWithRetry "aws cloudwatch put-metric-data --namespace ",namespace," --dimensions ",dimensions," --metric-name ",metric," --unit ",unit," --value ",data
 };
```

## Real-time Data Cluster

### Overview

- Real-time data will be shared between a cluster of EC2 Instances in an Auto Scaling group.
- The ASG will increase the number of instances throughout the day as more data is added to the cluster.
- At the end of the day, the day's data will be flushed, and the cluster will scale in.

The code to coordinate the RDB's queue is in the `.u.asg` namespace.
Its functions acts as wrappers around kdb-tick's `.u` functionality.
I.e., the functions will determine when to call `.u.sub` and `.u.del` in order to add and remove the subscriber from `.u.w`.

### Scaling the Cluster

On a high level the scaling method is quite simple.

1. A single RDB instance is launched and subscribes to the Tickerplant.
3. When it fills up with data a second RDB will come up to take its place.
4. This cycle repeats throughout the day growing the cluster.
5. At end of day all but the latest RDB instances are shutdown.

### The Subscriber Queue

There is one issue with the solution outlined above.
An RDB will not come up at the exact moment its predecessor unsubscribes.
So there are two scenarios that the Tickerplant must account for.

1. The new RDB comes up too early.
2. The new RDB does not come up in time.

If the RDB comes up too early, the Tickerplant must add it to a queue, while remembering the RDBs handle, and the tables it is subscribing for.
If it does this, it can add it to `.u.w` when it needs to.

If the RDB does not come up in time, the Tickerplant must remember the last `upd` message it sent to the previous RDB.
When the RDB eventually comes up it can use this to recover the missing data from the Tickerplant's log file.
This will prevent any gaps in the data.

The Tickerplant will store these details in `.u.asg.tab`.

```q
/ table used to handle subscriptions
/   time   - time the subscriber was added
/   handle - handle of the subscriber
/   tabs   - tables the subscriber has subscribed for
/   syms   - syms the subscriber has subscribed for
/   ip     - ip of the subscriber
/   queue  - queue the subscriber is a part of
/   live   - time the tickerplant addd the subscriber to .u.w
/   rolled - time the subscriber unsubscribed
/   firstI - upd count when subscriber became live
/   lastI  - last upd subscriber processed

.u.asg.tab: flip `time`handle`tabs`syms`queue`live`rolled`lastI!();

q).u.asg.tab
time handle tabs syms ip queue live rolled firstI lastI
-------------------------------------------------------

```

The first RDB to come up will first be added to this table and then it will immediately be added to `.u.w` and told to replay the log.
We will refer to the RDB that is in `.u.w` and therefore currently being published to as **live**.

When it is time to roll to the next subscriber the Tickerplant will query `.u.asg.tab` for the handle, tables and symbols of the next RDB in the queue and make it the new **live** subscriber.
kdb-ticks functionality will then take over and start publishing to the new RDB.

### Adding Subscribers

To be added to `.u.asg.tab`, a subscriber must call `.u.asg.sub`.

`.u.asg.sub` takes 3 parameters:

1. A list of tables to subscribe for.
2. A list of symbol lists to subscribe for (corresponding to the list of tables).
3. The name of the queue to subscribe to.

As we outlined earlier, the Tickerplant may immediately make a subscribing RDB the live subscriber.
This means the RDB cannot make multiple `.u.asg.sub` calls for each table and symbol list it wants from the Tickerplant.
Instead lists of the tables and symbol lists are sent in as parameters.
So multiple subscriptions can still be made.
\` can still be used to subscribe for all.

```q
/ t - A list of tables (or ` for all).
/ s - Lists of symbol lists for each of the tables.
/ q - The name of the queue to be added to.

.u.asg.sub:{[t;s;q]
    if[-11h = type t;
            t: enlist t;
            s: enlist s];

    if[not (=) . count each (t;s);
            '"Count of table and symbol lists must match"];

    if[not all missing: t in .u.t,`;
            '.Q.s1[t where not missing]," not available"];

    `.u.asg.tab upsert (.z.p; .z.w; t; s; `$"." sv string 256 vs .z.a; q; 0Np; 0Np; 0N; 0N);
    liveProc: select from .u.asg.tab where not null handle,
                                           not null live,
                                           null rolled,
                                           queue = q;

    if[not count liveProc; .u.asg.add[t;s;.z.w]];
 };
```

`.u.asg.sub` first makes some checks on the arguments:

- Ensure `t` and `s` are enlisted.
- Check that the count of `t` and `s` match.
- Check that all tables in `t` are available for subscription.

A record is than added to `.u.asg.tab` for the subscriber.

Finally `.u.asg.tab` is checked to see if there is another RDB in the queue.
If the queue is empty the Tickerplant will immediately make this RDB the **live** subscriber.

```q
q).u.asg.tab
time                          handle tabs syms ip       queue                                          live                          rolled firstI lastI
--------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7      ,`   ,`   10.0.1.5 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.13D23:36:43.518223000        0
q).u.w
Quote| 7i `
Trade| 7i `
```

If there is already a live subscriber the RDB will just be added to the queue.

```q
q).u.asg.tab
time                          handle tabs syms ip        queue                                          live                          rolled firstI lastI
---------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7                10.0.1.5  rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.13D23:36:43.518223000        0
2020.04.14D07:37:42.451523000 9                10.0.1.22 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg
q).u.w
Quote| 7i `
Trade| 7i `
```
### The Live Subscriber

To make an RDB the live the subscriber the Tickerplant will call `.u.asg.add`.

There are two instances when this is called:
1. When an RDB subscribes to a queue with no live subscriber.
2. When the Tickerplant is rolling subscribers.

```q
/ t - List of tables the RDB wants to subscribe to.
/ s - Symbol lists the RDB wants to subscribe to.
/ h - The handle of the RDB.

.u.asg.add:{[t;s;h]
    schemas: raze .u.subInner[;;h] .' flip (t;s);
    q: first exec queue from .u.asg.tab where handle = h;
    startI: max 0^ exec lastI from .u.asg.tab where queue = q;
    neg[h] (`.sub.rep; schemas; .u.L; (startI; .u.i));
    update live:.z.p, firstI:startI from `.u.asg.tab where handle = h;
 };
```

First `.u.subInner` is called to add the handle to `.u.w` for each table.
This function is equivalent to kdb-tick's `.u.sub` but it takes a handle as a third argument.

`.sub.rep` is called on the RDB.
The schemas, log file and the window in the log to replay passed down as arguments.
The log window is the gap between the last `upd` processed by the RDB's queue and `.u.i`, the current `upd` message.

Once the replay is kicked off on the RDB it is marked as the **live** subscriber in `.u.asg.tab`.

### Becoming the Live Subscriber

When the Tickerplant makes an RDB the **live** subscriber it will call `.sub.rep` to initialise it.

```q
/ schemas   - table names and schemas of subscription tables
/ tplog     - file path of the tickerplant log
/ logWindow - start and end of the window needed in the log, (start;end)

.sub.rep:{[schemas;tplog;logWindow]
    .sub.live: 1b;
    (.[;();:;].) each schemas;
    .sub.start: logWindow 0;
    `upd set .sub.replayUpd;
    -11!(logWindow 1;tplog);
    `upd set .sub.upd;
    .z.ts: .sub.monitorMemory;
    system "t 5000";
 };
```

The RDB first marks itself as live, then as in `tick/r.q` the RDBs will set the table schemas and replay the Tickerplant's log.

#### Replaying the Tickerplant Log

In kdb-tick `.u.i` will be sent to the RDB.
The RDB will then replay that many `upd` messages from the log.
As it replays it inserts every row of data in the `upd` messages into the tables.

We do not want to keep everything in the log as other RDBs in the cluster may be holding some of the day's data.
This is why the `logWindow` is passed down by the Tickerplant.

`logWindow` is a list of two integers:
1. The last `upd` message processed by the other RDBs in the same queue.
2. The last `upd` processed by the Tickerplant, `.u.i`.

To replay the log `.sub.start` is set to the first element of `logWindow` and `upd` is set to a `.sub.replayUpd` function.
The Tickerplant log replay is then kiked off with `-11!` until the second element in `logWindow` (`.u.i`).

`.sub.replayUpd` is then called for every `upd` message.
It increments `.sub.i` for every `upd` message until it reaches `.sub.start`.
From that point it calls `.sub.upd` to insert the data.

```q
.sub.replayUpd:{[t;data]
    if[.sub.i > .sub.start;
        if[not .sub.i mod 100; .sub.monitorMemory[]];
        .sub.upd[t;flip data];
        :(::);
        ];
    .sub.i+: 1;
 };

.sub.upd: {.sub.i+: 1; x upsert y};
```

One other function of `.sub.replayUpd` is to monitor the memory of the server while we are replaying.
This will protect the RDB in the case where there is too much data in the log to replay.
In this case the RDB will unsubscribe from the Tickerplant and another RDB will continue the replay.

After the log has been replayed `upd` is set to `.sub.upd`, this will `upsert` data and keep incrementing `.sub.i` for every `upd` the RDB receives.

The RDB then sets `.z.ts` to `.sub.monitorMemory` and initialises the timer to run every 5 seconds.

### Monitoring RDB Server Memory

The RDB monitors the memory of its server for two reasons:

1. To tell the Auto Scaling group to scale.
2. To stop subscribing from the Tickerplant.

```q
.sub.monitorMemory:{[]
    if[not .sub.scaled;
        if[.util.getMemUsage[] > .sub.scaleThreshold;
                .util.aws.scale .aws.groupName;
                .sub.scaled: 1b;
                ];
        :(::);
        ];
    if[.sub.live;
        if[.util.getMemUsage[] > .sub.rollThreshold;
                .sub.roll[];
                ];
        ];
 };
```

`.sub.monitorMemory` compares the percentage memory usage of the server against two thresholds.
These thresholds are set to two different global variables:

1. `.sub.scaleThreshold`
2. `.sub.rollThreshold`

When percentage memory usage rises above `.sub.scaleThreshold` the RDB will increment the Auto Scaling group's `DesiredCapacity` by calling `.util.aws.scale`.
It will also set `.sub.scaled` to be true to ensure the RDB does not scale the Auto Scaling group again.

When `.sub.rollThreshold` is hit the RDB will call `.sub.roll` on the Tickerplant.
This will make the Tickerplant roll to the next subscriber.

Ideally `.sub.scaleThreshold` and `.sub.rollThreshold` will be set far enough apart so that the new RDB has time to come up before `.sub.rollThreshold` is reached.
This will reduce the amount of `upd` messages the new RDB will have to replay.

### Rolling Subscribers

When `.sub.rollThreshold` is hit the RDB will call `.sub.roll` to unsubscribe from the Tickerplant.
From that point The RDB will not receive any more data, but it will be available to query.

```q
.sub.roll:{[]
    .sub.live: 0b;
    `upd set {[x;y] (::)};
    neg[.sub.TP] @ ({.u.asg.roll[.z.w;x]}; .sub.i);
 };
```

`.sub.roll` marks `.sub.live` as false and `upd` is set to do nothing so that no further `upd` messages are processed.
It will also call `.u.asg.roll` on the Tickerplant, using its own handle and `.sub.i` as arguments.

```q
/ h    - handle of the RDB
/ subI - last processed upd message

.u.asg.roll:{[h;subI]
    .u.del[;h] each .u.t;
    update rolled:.z.p, lastI:subI from `.u.asg.tab where handle = h;
    q: first exec queue from .u.asg.tab where handle = h;
    waiting: select from .u.asg.tab where not null handle,
                                          null live,
                                          queue = q;
    if[count waiting; .u.asg.add . first[waiting]`tabs`syms`handle];
 };
```

The Tickerplant marks the RDB that calls this function as **rolled** and `.sub.i` is stored in the `lastI` column.
It then uses kdb-tick's `.u.del` to delete the RDB's handle from `.u.w`.

Finally the Tickerplant searches `.u.asg.tab` for the next RDB in the queue.
If there is one it calls `.u.asg.add` making it the new **live** subscriber, and the cycle continues.

```q
q).u.asg.tab
time                          handle tabs syms ip         queue                                          live                          rolled                        firstI lastI
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7                10.0.1.5   rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.13D23:36:43.518223000 2020.04.14D08:13:05.942338000 0      9746
2020.04.14D07:37:42.451523000 9                10.0.1.22  rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D08:13:05.942400000                               9746
q).u.w
Quote| 9i `
Trade| 9i `
```

If there is no RDB ready in the queue, the next RDB to come up will immediately be added to `.u.w` and `.sub.i` will be used to recover from the Tickerplant log.

### End of Day

So throughout the day the RDB cluster will grow in size as the RDBs start, subscribe, fill and roll.
`.u.asg.tab` will look something like the table below.

```q
q).u.asg.tab
time                          handle tabs syms ip         queue                                          live                          rolled                        firstI lastI
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7                10.0.1.5   rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.13D23:36:43.518223000 2020.04.14D08:13:05.942338000 0      9746
2020.04.14D07:37:42.451523000 9                10.0.1.22  rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D08:13:05.942400000 2020.04.14D09:37:17.475790000 9746   19366
2020.04.14D09:14:14.831793000 10               10.0.1.212 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D09:37:17.475841000 2020.04.14D10:35:36.456220000 19366  29342
2020.04.14D10:08:37.606592000 11               10.0.1.196 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D10:35:36.456269000 2020.04.14D11:42:57.628761000 29342  39740
2020.04.14D11:24:45.642699000 12               10.0.1.42  rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D11:42:57.628809000 2020.04.14D13:09:57.867826000 39740  50112
2020.04.14D12:41:57.889318000 13               10.0.1.80  rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D13:09:57.867882000 2020.04.14D15:44:19.011327000 50112  60528
2020.04.14D14:32:22.817870000 14               10.0.1.246 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 2020.04.14D15:44:19.011327000                               60528
2020.04.14D16:59:10.663224000 15               10.0.1.119 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg
```

In the majority of systems, when end of day is called the data will be written to disk and flushed from the RDB.
In our case when we do this the **rolled** RDB's will be sitting idle with no data.

So `.u.asg.end` is called along with kdb-tick's `.u.end` in order to scale in.

```q
.u.asg.end:{[]
    notLive: exec handle from .u.asg.tab where not null handle,
                                        (null live) or not any null (live;rolled);
    neg[notLive] @\: (`.u.end; dt);
    delete from `.u.asg.tab where any (null handle; null live; not null rolled);
    update firstI:0 from `.u.asg.tab where not null live;
 };
```

The function first sends `.u.end` to all non live subscribers.
It then deletes these servers from `.u.asg.tab` and resets `firstI` to zero for all the live RDBs.

```q
q).u.asg.tab
time                          handle tabs syms ip         queue                                           live                          rolled firstI lastI
-----------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.14D15:32:22.817870000 14               10.0.1.246 rdb-clusters-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D15:44:19.011327000        0
```

When `.u.end` is called on the RDB it will delete the previous day's data from each table.
If the process is live it will mark `.sub.scaled` to false so that it can scale the ASG again.

If the RDB is not live and it has flushed all of its data it will call `.util.aws.terminate`.
This will both terminate the instance and reduce the `DesiredCapacity` of its ASG by one.

```q
.u.end: .sub.end;

.sub.end:{[dt]
    .sub.i: 0;
    .sub.clear dt+1;
 };

/ tm - clear all data from all tables before this time
.sub.clear:{[tm]
    ![;enlist(<;`time;tm);0b;`$()] each tables[];
    if[.sub.live;
            .sub.scaled:0b;
            .Q.gc[];
            :(::);
            ];
    if[not max 0, count each get each tables[];
            .util.aws.terminate .aws.instanceId];
 };
```


### Bringing it All Together

Starting the Tickerplant is the same as in kdb-tick, but `tickasg.q` is loaded instead of `tick.q`.

```bash
    q tickasg.q sym /mnt/efs/tplog -p 5010
```

#### tickasg.q

```q
system "l tick.q"
system "l asg/u.q"

.tick.zpc: .z.pc;
.z.pc: {.tick.zpc x; .u.asg.zpc x;};

.tick.end: .u.end;
.u.end: {.tick.end x; .u.asg.end x;};
```

`tickasg.q` starts by loading in `tick.q`, `.u.tick` is called in this file so the Tickerplant is started.
Loading in `asg/u.q` will initiate the `.u.asg` code on top of it.

`.z.pc` and `.u.end` are then overwritten to use both the `.u` and `.u.asg` versions.

```q
.u.asg.zpc:{[h]
    if[not null first exec live from .u.asg.tab where handle = h;
            .u.asg.roll[h;0]];
    update handle:0Ni from `.u.asg.tab where handle = h;
 };
```

`.u.asg.zpc` checks if the disconnecting RDB is the live subscriber if it is it calls `.u.asg.roll`.
It then marks the handle as null in `.u.asg.tab` for any disconnection.

There are also some minor changes made to `.u.add` and `.u.sub` in `asg/u.q`.

#### Changes to `.u`

`.u` will still work as normal with these changes.

The main change is needed because `.z.w` cannot be used in `.u.sub` or `.u.add` anymore.
When there is a queue of RDBs `.u.sub` will not be called in the RDBs initial subscription call so `.z.w` will not be the handle of the RDB we want to start publishing to.

To remediate this `.u.add` has been changed to take a handle as a third parameter instead of using `.z.w`.

The same change could not be made to `.u.sub` as it is the entry function for kdb-ticks `tick/r.q`.
To keep `tick/r.q` working `.u.subInner` has been added, it is a copy of `.u.sub` but takes a handle as a third parameter as needed, and it passes that handle into `.u.add`.
`.u.sub` is now a projection of `.u.subInner`, it passes `.z.w` in as the third parameter.

##### tick/u.q Versions
```q
\d .u
add:{$[(count w x)>i:w[x;;0]?.z.w;.[`.u.w;(x;i;1);union;y];w[x],:enlist(.z.w;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}
sub:{if[x~`;:sub[;y]each t];if[not x in t;'x];del[x].z.w;add[x;y]}
\d .
```

##### asg/u.q Versions
```q
/ use 'z' instead of .z.w
add:{$[(count w x)>i:w[x;;0]?z;.[`.u.w;(x;i;1);union;y];w[x],:enlist(z;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}

/ use 'z' instead of .z.w, and input as 3rd argument to .u.add
subInner:{if[x~`;:sub[;y;z]each t];if[not x in t;'x];del[x]z;add[x;y;z]}
sub:{subInner[x;y;.z.w]}

\d .
```

#### asg/r.q

When staring an RDB in autosacling mode `asg/r.q` is loaded instead of `tick/r.q`.

```bash
q asg/r.q 10.0.0.1:5010
```

Where `10.0.0.1` is the Private Ip address of the Tickerplant's server.

```q
/q asg/r.q [host]:port[:usr:pwd]

system "l asg/util.q"
system "l asg/sub.q"

while[null .sub.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];

.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

.sub.scaleThreshold: 60;
.sub.rollThreshold: 80;

.sub.live: 0b;
.sub.scaled: 0b;
.sub.rolled: 0b;

.sub.i: 0;

.u.end: {[dt] .sub.clear dt+1};

neg[.sub.TP] @ (`.u.asg.sub; `; `; `$ .aws.groupName, ".r-asg");
```

`asg/r.q` loads in the code to scale in `asg/util.q` and the code to subscribe and roll in `asg/sub.q`.
Opening its handle to the Tickerplant is done in a retry loop just in case the Tickerplant takes some time to initially come up.

It then sets the globals outlined below.

- `.aws.instanceId` - instance id of its EC2 instance.
- `.aws.groupName` - name of its Auto Scaling group.
- `.sub.scaleThreshold` - memory percentage threshold to scale out.
- `.sub.rollThreshold` - memory percentage threshold to unsubscribe.
- `.sub.live` - whether Tickerplant is currently it sending data.
- `.sub.scaled` - whether it has launched a new instance.
- `.sub.rolled` - whether it has unsubscribed.
- `.sub.i -` count of `upd` messages queue has processed.

## Cost/Risk Analysis

### Simulation

First we just want to see the cluster in action so we can see how it is behaving.
To do this we will run the cluster with `t3.micro` instances, these are only 1GB in size so we should see the cluster scaling out quite quickly.
The market will not generate data evenly throughout the day in the hypothetical example we used above.

Generally the data volumes will be highly concentrated when markets are open, to simulate this as closely as possible we will generate data in volumes with the distribution below.

| ![Data Volume Distribution](/ref/img/SimDataVolumes.png) |
|---|
| Figure X: Simulations Data Volume Distribution |

The behaviour of the cluster was monitored using Cloudwatch Metrics.
Each RDB server published the results of the linux `free` command.

First we will take a look at the total capacity of the cluster throughout the day.

| ![T3a Capacity By Server](/ref/img/SimT3aCapacityByServer.png) |
|---|
| Figure X: t3a.micro Cluster, Total Memory Cloudwatch Metric |

As expected we can see the number of servers stays at one data starts filling up the servers.
The RDBs then start receiving data and the cluster scales up to eight.
At end of day the data was flushed from memory, and all but the live servers were terminated.
So the capacity was reduced back to 1GB and cycle would continue.

Looking at each server we can see that the rates at which they filled up with memory were much higher in the middle of the day when the data volumes were highest.

| ![T3a Usage By Server](/ref/img/SimT3aUsageByServer.png) |
|---|
| Figure X: t3a.micro Servers, Memory Usage Cloudwatch Metric |

Focusing on just two of the servers we can see the relationship between the live server and the one it launches.

![T3a New Server](/ref/img/SimT3aScalingThresholds.png)
|---|
| Figure X: t3a.micro Servers, Scaling Thresholds and Memory Usage Cloudwatch Metric |


At 60% memory usage the live server increases the ASG's `DesiredCapacity` and launches the new server.
We can see the new server then waits for about twenty minutes until the live RDB reaches the roll threshold of 80%.
The live server then unsubscribes from the Tickerplant so the next server takes over and starts filling up.


### Cost Factors

Now that we can see the cluster working as expected we can take a look at its cost efficiency.
More specifically, how much of the computing resources we provisioned did we actually use.

To do that we can take a look at the capacity of the cluster versus its memory usage.

![T3a Capacity Vs Usage](/ref/img/SimT3aCapacityVsUsage.png)
|---|
| Figure X: t3a.micro Cluster, Total Memory vs Total Memory Usage  Cloudwatch Metrics |

We can see from the graph above that cluster's capacity follows the demand line quite closely.
To reduce costs even further we need to bring it closer.
Our first option is to reduce the size of each step up in capacity by reducing the size of our cluster's servers.
To bring the step closer to the demand line we need to either scale the server as late as possible or have each RDB hold more data.

To summarise there are 3 factors we can adjust in our cluster.

1. The server size.
2. The scale threshold.
3. The roll threshold.

#### Risk Analysis

Care will need to be taken when adjusting these factors for cost efficiency as each one will increase the margin for error.
First a roll threshold should be chosen so that the risk of losing an RDB to a `'wsfull` error is minimised.

The other risk comes from not being able to scale out fast enough.
This will occur if the lead time for an RDB server is greater than the time it takes for the live server to roll after it has scaled.

Taking a closer look at Figure X we can see the t3a.micro took around one minute to initialise.
It then waited another 22 minutes for the live server to climb to its roll threshold of 80% and took its place.

![T3a Wait Times](/ref/img/SimT3aWaitTimes.png)
|---|
| Figure X: t3a.micro Servers, wait time with Memory Usage Cloudwatch Metric |

So for this simulation the cluster had a 22 minute cushion.
With a one minute lead time, the data volumes would have to increase to 22 times that of the mock feed before the cluster starts to fall behind.

So we could probably afford to reduce this time by narrowing the gap between scaling and rolling, but it may not be worth it.
Falling behind the Tickerplant will mean recovering data from the it's log.
Each server that comes up will be farther and farther behind the Tickerplant.
More and more data will need to be recovered, and live data will be delayed.

One of the mantras of Auto Scaling is to stop guessing the demand on your system.
Keeping a cushion for the RDBs in the Tickerplant's queue will mean we never have to worry about large spikes in demand.
So the cost savings may not be worth it.

#### Server Size

The next simulation was ran to determine the impact of server size on the cost efficiency of the cluster.
Four different clusters were launched with four different instance types.
These clusters all had used different instance types with capacities of 2, 4, 8, 16GB.

![T3a Sizes Instance Types](/ref/img/SimSizesInstanceTypes.png)
|---|
| Figure X: t3a Instance Types for Cost Efficiency Comparison |

As in the first simulation data volumes were distributed in the pattern shown in figure X to try and simulate a day in the markets.
However, in this simulation we aimed to send in around 16GB of data to match the total capacity of one `t3a.xlarge`, the largest instance type of the clusters.

The first comparison needed was the upd throughput of each cluster.
`.sub.i` was published from each of the live RDBs allowing both the count and the rate of the messages processed to be plotted.

![T3a Sizes Upd Throughputs](/ref/img/SimSizesUpdThroughputs.png)
|---|
| Figure X: t3a Clusters Upd Throuput Cloudwatch Metrics |

Since there was no great difference between the clusters, the assumption could be made that the amount of data in each cluster at any given time throughout the day would be equivalent.
So any further comparisons between the 4 clusters would be valid.

Next the total capacity of each cluster was plotted.

![T3a Sizes Total Memory0](/ref/img/SimSizesTotalMemory0.png)
|---|
| Figure X: t3a Clusters |

Strangely the capacity t3a.small cluster, the smallest instance, rises above the capacity of the larger ones.
Intuitively they should scale together but the smaller steps of the `t3a.small` cluster should keep it below.
When the memory usage of each server is plotted we see that the smaller instances also rise above the larger ones.

When the cost of running each cluster was calculated we saw the same result, with the `t3a.small` costing more than the `t3a.medium`.

| Instance | Capacity (GB) | Total Cost | Cost Saving (%) |
|---|---|---|---|
| t3a.small | 1 | 3.7895 | 48 |
| t3a.medium | 2 | 3.5413 | 51 |
| t3a.large | 4 | 4.4493 | 38 |
| t3a.xlarge | 16 | 4.7175 | 35 |
| t3a.2xlarge | 32 | 7.2192 | 0 |

We can however still see that the two smaller instances see significant savings compared to the larger ones.
50% of the larger server compared to 35% for servers eight times the size.
If data volumes are scaled up the savings could become even more significant as the server's latent memory becomes less significant and the ratio of server size to demand becomes greater.
However, it is worth noting that the larger servers did have more capacity when the data volumes stopped, so the differences may also be slightly exaggerated.

![T3a Sizes Cost Vs Capacity](/ref/img/SimSizesCostVsCapacity.png)
|---|
| Figure X: t3a Clusters |

![T3a Sizes Memory Usage](/ref/img/SimSizesMemoryUsage.png)
|---|
| Figure X: t3a Clusters |

This comes down to the latent memory of each server, when an empty RDB server is running the memory usage is about 150 MB.

```bash
(base) [ec2-user@ip-10-0-1-212 ~]$  free
              total        used        free      shared  buff/cache   available
Mem:        2002032      150784     1369484         476      481764     1694748
Swap:             0           0           0
```

So for every instance we add to the cluster the memory usage of the cluster will increase by 150MB.
The extra 150MB will be negligible when the data volumes are scaled up as much larger servers will be used.
The difference is also less prominent in the 4, 8 and 16GB servers in this simulation, so going forward we will use them to compare costs.

![T3a Sizes Total Memory1](/ref/img/SimSizesTotalMemory1.png)
|---|
| Figure X: t3a Clusters |

The three clusters here behave as expected.
The smallest cluster's capacity, although it does move towards the larger ones as more instances are added to the cluster, stays far closer to the demand line.
This is worst case scenario for the `t3a.xlarge` cluster, as 16GBs means it has to scale up to safely meet the demand of the simulation's data, but the second server stays mostly empty until end of day.
The cluster will still have major savings over a `t3.2xlarge` with 32GB.

Taking a look at Figure X we can intuitively split the day up into three stages.

1. End of Day - Market Open.
2. Market Open - Market Close.
3. Market Close - End of Day.

Savings in the first stage will only be achieved by reducing size.
In the second stage savings look to be less significant, but will be achieved by both reducing server size and reducing the time in the queue of the servers.

From market close to end of day the clusters have scaled out fully.
In this stage cost efficiency will be determined by how much data is in the final server.
If when market closes it is only holding a small amount of data there will be idle capacity until end of day occurs.

This will be rather random and depend mainly on how much data is generated by the market.
Although having smaller servers will reduce the max amount of capacity that could be left unused.

However worst case scenario in this stage is that the amount of data held by the last live server falls in the range between the scale and roll thresholds.
This will mean an entire RDB server will be sitting idle until end of day.
To reduce the likelihood of this occurring it may be worth increasing the scale threshold and risking falling behind the Tickerplant in the case of high data volumes.

#### Threshold Windows


## Conclusion

Run through the pros and cons of the solution in the paper.
Give examples of how to take the solution further.
Table, sym sharding etc.
More granular autoscaling.
Writing down intraday.


## Appendix

### 1. Cloudformation Stack

### 2. Cloudwatch Metrics
#### bash
#### python
#### kdb+

### 3. Autoscaling Commands
#### bash
#### python
#### kdb+

### Simulation Cloudformation
