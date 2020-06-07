# RDB Auto Scaling for kdb+



## Introduction

Cloud computing has fast become the new normal.
The big cloud platforms like Amazon Web Services, Google Cloud, and Microsoft Azure have made it reliable, secure, and most importantly cost-effective.
The Infrastructure-as-a-Service (IaaS) model they have adopted means it is easier than ever before to provision computing resources.

This model has been taken a step further with Auto Scaling technologies.
Servers, storage and networking resources can now be commissioned and decommissioned in an instant.
Customers can leverage this new technology to scale their infrastructure in order to meet system demands without manual intervention.
This elasticity is one of the key benefits of Cloud Computing.
Systems can be scaled up quickly to meet demand without the complicated and time-consuming processes usually involved when provisioning new physical resources.

As these technologies become more prevalent it will become important to start incorporating them into kdb+.
In this paper we will explore how we can do this, in particular focusing on scaling the random access memory (RAM) needed for the real-time database.



## Auto Scaling

Auto Scaling is the act of monitoring the load on a system and dynamically acquiring or shutting down resources in order to match this load.
Incorporating this technology into an application means we no longer need to provision one large computing resource whose capacity must meet the application's demand throughout its lifetime.
Instead we can use clusters of smaller resources and scale them in and out to follow the demand curve.


### Auto Scaling and kdb+

There are three main types of computing resources that we can look to scale:

* Storage
* Compute
* Random-access memory (RAM)

Scaling storage for our kdb+ databases can be relatively simple in the cloud as the size or the number of storage volumes can just be increased as the database grows.
Alternatively an elastic file system could be used.
Amazon EFS is one example, it essentially gives unlimited storage capacity, you only pay for what you use and the read and write throughput of the system scales up as you write more data.

Reading or writing data are prime use cases for scaling compute power within a kdb+ application.
Scaling compute for reading has been covered by Rebecca Kelly in her blog post [Kx in the Public Cloud: Autoscaling using kdb+](https://kx.com/blog/kx-in-the-public-cloud-auto-scaling-using-kdb).
Here Rebecca demonstrates how to scale the number of historical database (HDB) servers to handle an increasing or decreasing number of queries.

Dynamically scaling the compute needed for writing can be a bit more complicated.
Given we want to maintain the data's order, a feed for a given data source must all go through one point in the system to be timestamped.

The same can be said for scaling the RAM needed for an RDB.
For this use case the number of RDB servers will be increased throughout the day as more and more data is ingested by the tickerplant.
The system must ensure that the data is not duplicated across these servers.
Solving this issue will be the objective of this paper.


### Auto Scaling the RDB

By Auto Scaling the RDB we will improve both the cost-efficiency and the availability of our databases.

#### Why use Auto Scaling

Let's say on average we will receive 12GB of data evenly throughout the day.
For a regular kdb+ system we will provision one server with 16GB of RAM, this will allow for some contingency capacity.
We then hope that the data volumes do not exceed that 16GB limit on a daily basis.

In a scalable cluster we can begin the day with one small server (for this example a quarter of the size, 4GB).
The RAM needed to hold real-time data in memory will grow throughout the day, and we can then step up our capacity by launching more servers.

| ![Large RDB Server](ref/img/ExampleCapacityComp.png) |
|---|
| Figure 1.1: Capacities of Regular and Scalable Real-time Databases |

#### Cost efficiency

In the cloud *you pay only for what you use*.
In a perfect system there should be no spare computing resources running idle accumulating costs.
We should be able to scale down in times of low demand like weekends when markets are closed or end-of-day when the day's data has been flushed from memory.
By ensuring this we can maintain the performance of a system at the lowest possible cost.

| ![Cost Savings](ref/img/ExampleASGCostEfficiency.png) |
|---|
| Figure 1.2: Potential Cost Savings of a Scalable RDB |

It is worth noting that the amount of servers you provision will have no real bearing on the overall cost.
You will pay the same for running one server with 16GBs of RAM as you would for running four servers with 4GBs.

Below is an example of Amazon Web Service's pricing for the varying sizes of its t3a instances.
As you can see the price is largely proportional to the memory capacity of each instance.

| ![T3 Prices](ref/img/T3aEc2Pricing.png) |
|---|
| Figure 1.3: Amazon Web Services' t3a instance pricing |


#### Availability

Most importantly, replacing the one large server with a scalable cluster will make our system more reliable.
With Auto Scaling technologies we can stop guessing our capacity needs.

By dynamically acquiring resources we can ensure that the load on our system never exceeds its capacity.
This will safeguard against unexpected spikes in data volumes crippling our systems.

| ![ASG Availability](ref/img/ExampleASGAvailability.png) |
|---|
| Figure 1.4: Availablity of a Scalable RDB under High Load |

When developing a new application there is no need to estimate how much memory the RDB is going to need throughout its lifetime.
Even if the estimate turns out to be correct, we will still end up provisioning resources that will lie mostly idle during periods of low demand.
Demand varies and so should our capacity.

Distributing the day's data among multiple smaller servers will also increase the system's resiliency.
One fault will no longer mean all of the day's data is lost. 
The smaller RDBs will also be quicker to recover from a fault as they will only have to replay a portion of the tickerplant's log.



## Amazon Web Services (AWS)

Amazon Web Services (AWS) was used to deploy the solution outlined in this paper.
The AWS resources needed to do so are described in this section.
These should all be transferable to the other big cloud platforms like Microsoft Azure and Google Cloud.


### Amazon Machine Image (AMI)

As multiple servers will be launched, all needing kdb+ and the code to scale the RDBs, an Amazon Machine Image was needed.
An AMI is a template that Amazon's Elastic Compute Cloud (EC2) uses to start instances.
Creating one with our code and software means we can provision multiple EC2 instances with identical software, this will ensure consistency across our stack.

To do this a regular EC2 instance was launched using Amazon's Linux 2 AMI, kdb+ was installed and our code was deployed.
The Amazon command-line Interface (CLI) was then used to create an image of the server.

```bash
aws ec2 create-image --instance-id i-1234567890abcdef --name kdb-rdb-autoscaling-ami-v1
```

This could also be done using the AWS Console.
Once available the AMI was used along with Cloudformation deploy a stack.


### Cloudformation

AWS Cloudformation allows the customer to use a `YAML` file to provision resources.
The resources needed in our stack are outlined below.

- AWS Elastic File System (EFS).
- EC2 launch templates.
- Auto Scaling groups.

An example `YAML` file to deploy this Stack can be found in [Appendix 1](#1-cloudformation-template).


#### AWS Elastic File System (EFS)

EFS is a Network File System (NFS) which any EC2 instance can mount.
This solves the first problem we will face when putting the tickerplant and RDB on different servers.
Without a common file system the RDB would not be able to replay the tickerplant's log file to recover.

#### EC2 launch template

On AWS, launch templates can be used to configure details for an EC2 instance ahead of time (e.g. instance type, root volume size, AMI id).
Our Auto Scaling groups will use these templates to launch their servers.


### Auto Scaling group (ASG)

AWS EC2 Auto Scaling groups (ASG) can be used to maintain a given number of EC2 instances in a cluster.
If any of the instances in the clusters become unhealthy the ASG will terminate them and launch new ones in their place, maintaining the overall compute capacity of the group.

##### Recovery

The first Auto Scaling group we deploy will be for the tickerplant.
Even though there will only ever be one instance for the tickerplant we are still putting it in an ASG for recovery purposes.
If it goes down the ASG will automatically start another one.

##### Scalability

There are a number of ways an ASG can scale its instances on AWS:

- Scheduled
    * Set timeframes to scale in and out.
- Predictive
    * Machine learning is used to predict demand.
- Dynamic
    * Cloudwatch Metrics are monitored to follow the flow of demand.
    * e.g. CPU and Memory Usage.
- Manual
    * Adjusting the ASG's `DesiredCapacity` attribute.
    * Can be done through the console or the AWS CLI.


#### Dynamic Scaling

We could conceivably publish Cloudwatch metrics for memory usage from our RDBs and allow AWS to manage scaling out.
If the memory across the cluster rises to a certain point the ASG will increment its `DesiredCapacity` attribute and launch a new server.

Sending custom Cloudwatch metrics is relatively simple using either python's boto3 library or the AWS CLI.
Examples of how to use these can be found in [Appendix 2](#2-cloudwatch-metric-commands).

#### Manual scaling

Another way to scale the instances in an ASG, and the method more suitable for our use case, is to manually adjust the ASG's `DeciredCapacity`.
This can be done via the AWS console or the AWS CLI.

As it can be done using the CLI we can program the RDBs to scale the cluster in and out.
Managing the Auto Scaling within the application is preferable because we want to be specific when scaling in.

To scale in, AWS will choose which instance to terminate based on certain criteria (e.g. instance count per Availability Zone, time to the next next billing hour).
You are able to replace the default behaviour with other options like `OldestInstance` and `NewestInstance`.

However, if all of the criteria have been evaluated and there are still multiple instances to choose from, AWS will pick one at random.

Under no circumstance do we want AWS to terminate an instance running an RDB process which is still holding today's data.
So we will need to keep control of the Auto Scaling group's `DesiredCapacity` within the application.

As with publishing Cloudwatch metrics, adjusting the `DesiredCapacity` can be done with python's boto3 library or the AWS CLI.
[Appendix 3](#3-auto-scaling-group-commands) has examples of how to use these.

#### Auto Scaling in q

As the AWS CLI simply uses unix commands we can run them in `q` using the `system` command.
If we configure the CLI to return `json` we can then parse the output using `.j.k`.
It will be useful to wrap the `aws` system commands in a retry loop as they may timeout when AWS is under load.

```q
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

To increment the capacity we can use the `aws autoscaling` to find the current `DesiredCapacity`.
Once we have this we can add one and set the attribute.
The ASG will then automatically launch a server.

```q
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
When doing this it must make an `autoscaling` call instead of an `ec2` one.
The ASG to which it calls will then know not to launch a new instance in its place.

```q
.util.aws.terminate:{[instanceId]
    .j.k "\n" sv .util.sys.runWithRetry "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"
 };
```



## Real-time data cluster


### Overview

Instead of one large instance, our RDB will now be a cluster of smaller instances and the day's real-time data will be distributed among them.
An Auto Scaling group will be used to maintain the RAM capacity of the cluster.
Throughout the day more data will be ingested by the tickerplant and added to the cluster.
The ASG will increase the number of instances in the cluster throughout the day in order to hold this new data.
At the end of the day, the day's data will be flushed from memory and the ASG will scale the cluster in.


#### kdb+tick

The code in this paper has been written to act as a wrapper around [kdb+tick's](https://github.com/KxSystems/kdb-tick) `.u` functionality.
The code to coordinate the RDBs is placed in the `.u.asg` namespace and its functions will determine when to call `.u.sub` and `.u.del` in order to add and remove the subscriber from `.u.w`.


### Scaling the cluster

On a high level the scaling method is quite simple.

1. A single RDB instance is launched and subscribes to the tickerplant.
2. When it fills up with data a second RDB will come up to take its place.
3. This cycle repeats throughout the day growing the cluster.
4. At end-of-day all but the latest RDB instances are shutdown.


### The subscriber queue

There is one issue with the solution outlined above.
An RDB will not come up at the exact moment its predecessor unsubscribes.
So there are two scenarios that the tickerplant must account for.

* The new RDB comes up too early.
* The new RDB does not come up in time.

If the RDB comes up too early, the tickerplant must add it to a queue, while remembering the RDB's handle, and the subscription info.
If it does this, it can add it to `.u.w` when it needs to.

If the RDB does not come up in time, the tickerplant must remember the last `upd` message it sent to the previous RDB.
When the RDB eventually comes up it can use this to recover the missing data from the tickerplant's log file.
This will prevent any gaps in the data.

The tickerplant will store these details in `.u.asg.tab`.

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

The first RDB to come up will be added to this table and `.u.w`, it will then be told to replay the log.
We will refer to the RDB that is in `.u.w` and therefore currently being published to as **live**.

When it is time to roll to the next subscriber the Tickerplant will query `.u.asg.tab`.
It will look for the handle, tables and symbols of the next RDB in the queue and make it the new **live** subscriber.
kdb+tick's functionality will then take over and start publishing to the new RDB.


### Adding subscribers

To be added to `.u.asg.tab` a subscriber must call `.u.asg.sub` which takes three parameters:

1. A list of tables to subscribe for.
2. A list of symbol lists to subscribe for (corresponding to the list of tables).
3. The name of the queue to subscribe to.

If the RDB is subscribing to a queue with no **live** subscriber, the tickerplant will immediately add it to `.u.w` and tell it to replay the log.
This means the RDB cannot make multiple `.u.asg.sub` calls for each table it wants from the tickerplant.
Instead table and symbol lists are sent as parameters.
So multiple subscriptions can still be made.

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

A record is then added to `.u.asg.tab` for the subscriber.
Finally, `.u.asg.tab` is checked to see if there is another RDB in the queue.
If the queue is empty the tickerplant will immediately make this RDB the **live** subscriber.

```q
q).u.asg.tab
time                          handle tabs syms ip       queue                                          live                          rolled firstI lastI
--------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7      ,`   ,`   10.0.1.5 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.13D23:36:43.518223000        0
q).u.w
Quote| 7i `
Trade| 7i `
```

If there is already a live subscriber the RDB will just be added to the queue.

```q
q).u.asg.tab
time                          handle tabs syms ip        queue                                          live                          rolled firstI lastI
---------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7                10.0.1.5  rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.13D23:36:43.518223000        0
2020.04.14D07:37:42.451523000 9                10.0.1.22 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg 
q).u.w
Quote| 7i `
Trade| 7i `
```

### The live subscriber


To make an RDB the live subscriber the tickerplant will call `.u.asg.add`.
There are two instances when this is called:

1. When an RDB subscribes to a queue with no live subscriber.
2. When the tickerplant is rolling subscribers.

```q
/ t - List of tables the RDB wants to subscribe to.
/ s - Symbol lists the RDB wants to subscribe to.
/ h - The handle of the RDB.

.u.asg.add:{[t;s;h]
    schemas: raze .u.subInner[;;h] .' flip (t;s);
    q: first exec queue from .u.asg.tab where handle = h;
    startI: max 0^ exec lastI from .u.asg.tab where queue = q;
    neg[h] @ (`.sub.rep; schemas; .u.L; (startI; .u.i));
    update live:.z.p, firstI:startI from `.u.asg.tab where handle = h;
 };
```

First `.u.subInner` is called to add the handle to `.u.w` for each table.
This function is equivalent to kdb+tick's `.u.sub` but it takes a handle as a third argument.

The tickerplant then calls `.sub.rep` on the RDB.
The schemas, log file and the window in the log to replay are passed down as arguments.
The log window is the gap between the last `upd` processed by the RDB's queue and `.u.i`, the current `upd` message.

Once the replay is kicked off on the RDB it is marked as the **live** subscriber in `.u.asg.tab`.


### Becoming the live subscriber

When the tickerplant makes an RDB the **live** subscriber it will call `.sub.rep` to initialize it.

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

The RDB first marks itself as live, then as in `tick/r.q` the RDBs will set the table schemas and replay the tickerplant's log.


#### Replaying the tickerplant log

In kdb+tick `.u.i` will be sent to the RDB.
The RDB will then replay that many `upd` messages from the log.
As it replays it inserts every row of data in the `upd` messages into the tables.

We do not want to keep everything in the log as other RDBs in the cluster may be holding some of the day's data.
This is why the `logWindow` is passed down by the tickerplant.

`logWindow` is a list of two integers:
1. The last `upd` message processed by the other RDBs in the same queue.
2. The last `upd` processed by the tickerplant, `.u.i`.


To replay the log `.sub.start` is set to the first element of `logWindow` and `upd` is set to `.sub.replayUpd`.
The tickerplant log replay is then kicked off with `-11!` until the second element in the `logWindow`, `.u.i`.

`.sub.replayUpd` is then called for every `upd` message.
With each `upd` it increments `.sub.i` until it reaches `.sub.start`.
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
In this case the RDB will unsubscribe from the tickerplant and another RDB will continue the replay.

After the log has been replayed `upd` is set to `.sub.upd`, this will `upsert` data and keep incrementing `.sub.i` for every `upd` the RDB receives.
Finally the RDB sets `.z.ts` to `.sub.monitorMemory` and initialises the timer to run every five seconds.


### Monitoring RDB server memory

The RDB monitors the memory of its server for two reasons:

1. To tell the Auto Scaling group to scale up.
2. To unsubscribe from the tickerplant when it is full.

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

When `.sub.rollThreshold` is hit the RDB will call `.sub.roll` on the tickerplant.
This will make the tickerplant roll to the next subscriber.

Ideally `.sub.scaleThreshold` and `.sub.rollThreshold` will be set far enough apart so that the new RDB has time to come up before `.sub.rollThreshold` is reached.
This will prevent the cluster from falling behind the tickerplant and reduce the number of `upd` messages that will need to be recovered from the log.


### Rolling subscribers

When `.sub.rollThreshold` is hit the RDB will call `.sub.roll` to unsubscribe from the tickerplant.
From that point The RDB will not receive any more data, but it will be available to query.

```q
.sub.roll:{[]
    .sub.live: 0b;
    `upd set {[x;y] (::)};
    neg[.sub.TP] @ ({.u.asg.roll[.z.w;x]}; .sub.i);
 };
```

`.sub.roll` marks `.sub.live` as false and `upd` is set to do nothing so that no further `upd` messages are processed.
It will also call `.u.asg.roll` on the tickerplant, using its own handle and `.sub.i` (the last `upd` it has processed) as arguments.

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

`.u.asg.roll` uses kdb+tick's `.u.del` to delete the RDB's handle from `.u.w`.
It then marks the RDB as **rolled** and `.sub.i` is stored in the `lastI` column.
Finally `.u.asg.tab` is queried for the next RDB in the queue.
If there is one it calls `.u.asg.add` making it the new **live** subscriber and the cycle continues.

```q
q).u.asg.tab
time                          handle tabs syms ip         queue                                          live                          rolled                        firstI lastI
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7                10.0.1.5   rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.13D23:36:43.518223000 2020.04.14D08:13:05.942338000 0      9746
2020.04.14D07:37:42.451523000 9                10.0.1.22  rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D08:13:05.942400000                               9746
q).u.w
Quote| 9i `
Trade| 9i `
```

If there is no RDB ready in the queue, the next RDB to come up will immediately be added to `.u.w` and `lastI` will be used to recover from the tickerplant log.


### End of day

Throughout the day the RDB cluster will grow in size as the RDBs start, subscribe, fill and roll.
`.u.asg.tab` will look something like the table below.

```q
q).u.asg.tab
time                          handle tabs syms ip         queue                                          live                          rolled                        firstI lastI
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.13D23:36:43.518172000 7                10.0.1.5   rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.13D23:36:43.518223000 2020.04.14D08:13:05.942338000 0      9746
2020.04.14D07:37:42.451523000 9                10.0.1.22  rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D08:13:05.942400000 2020.04.14D09:37:17.475790000 9746   19366
2020.04.14D09:14:14.831793000 10               10.0.1.212 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D09:37:17.475841000 2020.04.14D10:35:36.456220000 19366  29342
2020.04.14D10:08:37.606592000 11               10.0.1.196 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D10:35:36.456269000 2020.04.14D11:42:57.628761000 29342  39740
2020.04.14D11:24:45.642699000 12               10.0.1.42  rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D11:42:57.628809000 2020.04.14D13:09:57.867826000 39740  50112
2020.04.14D12:41:57.889318000 13               10.0.1.80  rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D13:09:57.867882000 2020.04.14D15:44:19.011327000 50112  60528
2020.04.14D14:32:22.817870000 14               10.0.1.246 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg  2020.04.14D15:44:19.011327000                               60528
2020.04.14D16:59:10.663224000 15               10.0.1.119 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg
```

Usually when end of day occurs `.u.end` is called in the tickerplant.
It informs the RDB and the data will then be written to disk and flushed from memory.
In our case when we do this the **rolled** RDBs will be sitting idle with no data.

To scale in `.u.asg.end` is called alongside kdb+tick's `.u.end`.

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
It then deletes these servers from `.u.asg.tab` and resets `firstI` to zero for all of the live RDBs.

```q
q).u.asg.tab
time                          handle tabs syms ip         queue                                           live                          rolled firstI lastI
-----------------------------------------------------------------------------------------------------------------------------------------------------------
2020.04.14D15:32:22.817870000 14               10.0.1.246 rdb-cluster-v1-RdbASGMicro-NWN25W2UPGWQ.r-asg   2020.04.14D15:44:19.011327000        0
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


### Bringing it all together

The q scripts for the code outlined above are laid out in the same way as kdb+tick i.e. the script to run the tickerplant, `tickasg.q`, is in the top directory with the `.u` and RDB code in a directory below, `asg/`.

The code runs alongside kdb+tick so its scripts are placed in the same top directory.

```bash
$ tree q/
q
├── asg
│   ├── mon.q
│   ├── r.q
│   ├── sub.q
│   ├── u.q
│   └── util.q
├── tick
│   ├── r.q
│   ├── sym.q
│   ├── u.q
│   └── w.q
├── tickasg.q
└── tick.q
```

Starting the tickerplant is the same as in kdb+tick, but `tickasg.q` is loaded instead of `tick.q`.

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

`tickasg.q` starts by loading in `tick.q`, `.u.tick` is called in this file so the tickerplant is started.
Loading in `asg/u.q` will initiate the `.u.asg` code on top of it.

`.z.pc` and `.u.end` are then overwritten to use both the `.u` and `.u.asg` versions.

```q
.u.asg.zpc:{[h]
    if[not null first exec live from .u.asg.tab where handle = h;
            .u.asg.roll[h;0]];
    update handle:0Ni from `.u.asg.tab where handle = h;
 };
```

`.u.asg.zpc` checks if the disconnecting RDB is the live subscriber and calls `.u.asg.roll` if so.
It then marks the handle as null in `.u.asg.tab` for any disconnection.

There are also some minor changes made to `.u.add` and `.u.sub` in `asg/u.q`.

#### Changes to `.u`

`.u` will still work as normal with these changes.

The main change is needed because `.z.w` cannot be used in `.u.sub` or `.u.add` anymore.
When there is a queue of RDBs `.u.sub` will not be called in the RDB's initial subscription call, so `.z.w` will not be the handle of the RDB we want to start publishing to.
To remedy this `.u.add` has been changed to take a handle as a third parameter instead of using `.z.w`.

The same change could not be made to `.u.sub` as it is the entry function for kdb+ticks `tick/r.q`.
To keep `tick/r.q` working `.u.subInner` has been added, it is a copy of `.u.sub` but takes a handle as a third parameter.
`.u.sub` is now a projection of `.u.subInner`, it passes `.z.w` in as the third parameter.

##### tick/u.q
```q
\d .u
add:{$[(count w x)>i:w[x;;0]?.z.w;.[`.u.w;(x;i;1);union;y];w[x],:enlist(.z.w;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}
sub:{if[x~`;:sub[;y]each t];if[not x in t;'x];del[x].z.w;add[x;y]}
\d .
```

##### asg/u.q
```q
/ use 'z' instead of .z.w
add:{$[(count w x)>i:w[x;;0]?z;.[`.u.w;(x;i;1);union;y];w[x],:enlist(z;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}

/ use 'z' instead of .z.w and input as 3rd argument to .u.add
subInner:{if[x~`;:subInner[;y;z]each t];if[not x in t;'x];del[x]z;add[x;y;z]}
sub:{subInner[x;y;.z.w]}

\d .
```

#### asg/r.q

When starting an RDB in Auto Scaling mode `asg/r.q` is loaded instead of `tick/r.q`.

```bash
q asg/r.q 10.0.0.1:5010
```

Where `10.0.0.1` is the private IP address of the tickerplant's server.

```q
/q asg/r.q [host]:port[:usr:pwd]

system "l asg/util.q"
system "l asg/sub.q"

while[null .sub.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];

.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

.sub.scaleThreshold: getenv `SCALETHRESHOLD;
.sub.rollThreshold: getenv `ROLLTHRESHOLD;

.sub.live: 0b;
.sub.scaled: 0b;

.sub.i: 0;

.u.end: {[dt] .sub.clear dt+1};

neg[.sub.TP] @ (`.u.asg.sub; `; `; `$ .aws.groupName, ".r-asg");
```

`asg/r.q` loads the scaling code in `asg/util.q` and the code to subscribe and roll in `asg/sub.q`.
Opening its handle to the tickerplant is done in a retry loop just in case the tickerplant takes some time to initially come up.

It then sets the global variables outlined below:

- `.aws.instanceId` - instance id of its EC2 instance.
- `.aws.groupName` - name of its Auto Scaling group.
- `.sub.scaleThreshold` - memory percentage threshold to scale out.
- `.sub.rollThreshold` - memory percentage threshold to unsubscribe.
- `.sub.live` - whether tickerplant is currently it sending data.
- `.sub.scaled` - whether it has launched a new instance.
- `.sub.i -` count of `upd` messages queue has processed.



## Cost/Risk analysis

To determine how much cost savings our cluster of RDBs can make we will deploy and simulate a day in the market.

### Initial simulation

First we just want to see the cluster in action so we can see how it behaves.
To do this we will run the cluster with `t3.micro` instances. These are only 1GB in size so we should see the cluster scaling out quite quickly.
The market will not generate data evenly throughout the day in the hypothetical example we used in the [Auto Scaling Section](#auto-scaling) above.

Generally the data volumes will be highly concentrated while the markets are open and quite sparse otherwise.
To simulate this as closely as possible we will generate data in volumes with the distribution below.

| ![Data Volume Distribution](ref/img/SimDataVolumes.png) |
|---|
| Figure 2.1: Simulation Data Volume Distribution |

The behavior of the cluster was monitored using Cloudwatch metrics.
Each RDB server published the results of the Linux `free` command.
First we will take a look at the total capacity of the cluster throughout the day.

| ![T3a Capacity By Server](ref/img/SimT3aCapacityByServer.png) |
|---|
| Figure 2.2: Total Memory Capacity of the t3a.micro Cluster - Cloudwatch Metrics |

As expected we can see the number of servers stayed at one until the market opened.
The RDBs then started to receive data and the cluster scaled up to eight.
At end-of-day the data was flushed from memory and all but the live server was terminated.
So the capacity was reduced back to 1GB and the cycle continued the day after.

Looking at each server we can see that the rates at which they filled up with memory were much higher in the middle of the day when the data volumes were highest.

| ![T3a Usage By Server](ref/img/SimT3aUsageByServer.png) |
|---|
| Figure 2.3: Memory Usage of each of the t3a.micro Servers - Cloudwatch Metrics |

Focusing on just two of the servers we can see the relationship between the live server and the one it eventually launches.

| ![T3a New Server](ref/img/SimT3aScalingThresholds.png) |
|---|
| Figure 2.4: Scaling Thresholds of t3a.micro Servers - Cloudwatch Metrics |

At 60% memory usage the live server increased the ASG's `DesiredCapacity` and launched the new server.
We can see the new server then waited for about twenty minutes until the live RDB reached the roll threshold of 80%.
The live server then unsubscribed from the tickerplant and the next server took over.


### Cost factors

Now that we can see the cluster working as expected we can take a look at its cost-efficiency.
More specifically, how much of the computing resources we provisioned did we actually use.

To do that we can take a look at the capacity of the cluster versus its memory usage.

| ![T3a Capacity Vs Usage](ref/img/SimT3aCapacityVsUsage.png) |
|---|
| Figure 2.5: t3a.micro Cluster's Total Memory Capacity vs Total Memory Usage - Cloudwatch Metrics |

We can see from the graph above that the cluster's capacity follows the demand line quite closely.
To reduce costs further we need to bring it even closer.

Our first option is to reduce the size of each step up in capacity by reducing the size of our cluster's servers.
To bring the step itself closer to the demand line we need to either scale the server as late as possible or have each RDB hold more data.

To summarise there are three factors we can adjust in our cluster:

1. The server size.
2. The scale threshold.
3. The roll threshold.

#### Risk analysis

Care will be needed when adjusting these factors for cost-efficiency as each one will increase the margin for error.
First a roll threshold should be chosen so that the risk of losing an RDB to a `'wsfull` error is minimized.

The other risk comes from not being able to scale out fast enough.
This will occur if the lead time for an RDB server is greater than the time it takes for the live server to roll after it has scaled.

Taking a closer look at Figure 2.4 we can see the t3a.micro took around one minute to initialize.
It then waited another 22 minutes for the live server to climb to its roll threshold of 80% and took its place.

| ![T3a Wait Times](ref/img/SimT3aWaitTimes.png) |
|---|
| Figure 2.6: t3a.micro Server Waiting to Become the Live Subscriber - Cloudwatch Metric |

So for this simulation the cluster had a 22-minute cushion.
With a one minute lead time, the data volumes would have to increase to 22 times that of the mock feed before the cluster starts to fall behind.

So we could probably afford to reduce this time by narrowing the gap between scaling and rolling, but it may not be worth it.

Falling behind the tickerplant will mean recovering data from its log.
This issue will be a compounding one as each subsequent server that comes up will be farther and farther behind the tickerplant.
More and more data will need to be recovered, and live data will be delayed.

One of the mantras of Auto Scaling is to *"stop guessing demand"*.
Keeping a cushion for the RDBs in the tickerplant's queue will most likely not have to worry about large spikes in demand affecting our system.

Further simulations will be run to determine whether adjusting these factors is worth the risk.


### Server size comparison

Comparing the cost savings while running clusters of different sizes will help to determine the impact of server size on the cost-efficiency of the cluster.
Four different clusters were launched with four different instance types.
These clusters all had used different instance types with capacities of 2, 4, 8, and 16GB.

| ![T3a Sizes Instance Types](ref/img/SimSizesInstanceTypes.png) |
|---|
| Figure 3.1: t3a Instance Types Used for Cost Efficiency Comparison |

As in the first simulation, data volumes were distributed in the pattern shown in Figure 2.1 in order to simulate a day in the markets.
However, in this simulation we aimed to send in around 16GB of data to match the total capacity of one `t3a.xlarge`, the largest instance type of the clusters.

The first comparison was the upd throughput of each cluster.
`.sub.i` was published from each of the live RDBs allowing both the count and the rate of the messages processed to be plotted.

| ![T3a Sizes Upd Throughputs](ref/img/SimSizesUpdThroughputs.png) |
|---|
| Figure 3.2: t3a Cluster's Upd Throughput - Cloudwatch Metrics |

Since there was no great difference between the clusters, the assumption could be made that the amount of data in each cluster at any given time throughout the day would be equivalent.
So any further comparisons between the four clusters would be valid.
Next the total capacity of each cluster was plotted.

| ![T3a Sizes Total Memory0](ref/img/SimSizesTotalMemory0.png) |
|---|
| Figure 3.3: t3a Clusters' Total Memory Capacity |

Strangely the capacity of the `t3a.small` cluster, the smallest instance, rose above the capacity of the larger ones.
Intuitively they should scale together but the smaller steps of the `t3a.small` cluster should still have kept it below the others.
When the memory usage of each server is plotted we see that the smaller instances once again rose above the larger ones.

| ![T3a Sizes Memory Usage](ref/img/SimSizesMemoryUsage.png) |  
|---|
| Figure 3.4: t3a Clusters' Memory Usage - Cloudwatch Metrics |

This comes down to the latent memory of each server, when an empty RDB server is running the memory usage is approximately 150 MB.

```bash
(base) [ec2-user@ip-10-0-1-212 ~]$  free
              total        used        free      shared  buff/cache   available
Mem:        2002032      150784     1369484         476      481764     1694748
Swap:             0           0           0
```

So for every instance we add to the cluster the overall memory usage will increase by 150MB.
The extra 150MB will be negligible when the data volumes are scaled up as much larger servers will be used.
The difference is less prominent in the 4, 8, and 16GB servers in this simulation, so going forward we will use them to compare costs.

| ![T3a Sizes Total Memory1](ref/img/SimSizesTotalMemory1.png) |
|---|
| Figure 3.5: Larger t3a Clusters' Memory Usage - Cloudwatch Metrics |

The cost of running each cluster was calculated below.

| Instance | Capacity (GB) | Total Cost ($) | Cost Saving (%) |
|---|---|---|---|
| t3a.small | 1 | 3.7895 | 48 |
| t3a.medium | 2 | 3.5413 | 51 |
| t3a.large | 4 | 4.4493 | 38 |
| t3a.xlarge | 16 | 4.7175 | 35 |
| t3a.2xlarge | 32 | 7.2192 | 0 |

We can see that the two smaller instances have significant savings compared to the larger ones.
50% savings when compared to running a `t3a.2xlarge`.
The clusters with larger instances saw just 35 and 38%.

| ![T3a Sizes Cost Vs Capacity](ref/img/SimSizesCostVsCapacity.png) |
|---|
| Figure 3.6: t3a Clusters' Cost Savings |

If data volumes are scaled up the savings could become even greater as the server's latent memory becomes less significant and the ratio of server size to demand becomes greater.
However it is worth noting that the larger servers did have more capacity when the data volumes stopped, so the differences may also be slightly exaggerated.

The three clusters here behave as expected.
The smallest cluster's capacity, although it does move towards the larger ones as more instances are added to the cluster, stays far closer to the demand line.
This is the worst-case scenario for the `t3a.xlarge` cluster, as 16GBs means it has to scale up to safely meet the demand of the simulation's data, but the second server stays mostly empty until end of day.
The cluster will still have major savings over a `t3.2xlarge` with 32GB.

Taking a look at Figure 3.5 we can intuitively split the day into three stages:


1. End of Day - Market Open.
2. Market Open - Market Close.
3. Market Close - End of Day.

Savings in the first stage will only be achieved by reducing the instance size.
In the second stage savings look to be less significant, but could be achieved by both reducing server size and reducing the time in the queue of the servers.

From market-close to end-of-day the clusters have scaled out fully.
In this stage cost-efficiency will be determined by how much data is in the final server.
If when the market closes it is only holding a small amount of data there will be idle capacity until end-of-day occurs.

This will be rather random and depend mainly on how much data is generated by the market.
Although having smaller servers will reduce the maximum amount of capacity that could be left unused.

The worst-case scenario in this stage is that the amount of data held by the last live server falls in the range between the scale and roll thresholds.
This will mean an entire RDB server will be sitting idle until end-of-day.
To reduce the likelihood of this occurring it may be worth increasing the scale threshold and risking falling behind the tickerplant in the case of high data volumes.

#### Threshold window comparison

To test the effects, the scale threshold on cost another stack was launched also with four RDB clusters.
In this stack all four clusters used `t3a.medium` EC2 instances (4GB) and a roll threshold of 85% was set.
Data was generated in the same fashion as the previous simulation.

The scale thresholds were set to 20, 40, 60, and 80% and the memory capacity was plotted as in Figure 3.4.

| ![T3a Thresholds Total Memory All](ref/img/SimT3aThresholdsTotalMemoryAll.png) |
|---|
| Figure 4.1: t3a.medium Clusters' Memory Capacity vs Memory Usage - Cloudwatch Metrics |

As expected the clusters with the lower scale thresholds scale out farther away from the demand line.
Their new servers will then have a longer wait time in the tickerplant queue.
This will reduce the risks associated with the second stage but also increase its costs.
This difference can be seen more clearly if only the 20 and 80% clusters are plotted.

| ![T3a Thresholds Total Memory 20 80](ref/img/SimT3aThresholdsTotalMemory2080.png) |
|---|
| Figure 4.2: t3a.medium 20 and 80% Clusters' Memory Capacity vs Memory Usage - Cloudwatch Metrics |

Most importantly we can see that in the third stage the clusters with lower thresholds started an extra server.
So a whole instance was left idle in those clusters from market-close to end-of-day.
The costs associated with each cluster were calculated below.

| Instance | Threshold | Capacity (GB) | Total Cost ($) | Cost Saving (%) |
|---|---|---|---|---|
| t3a.medium | 80% | 4 | 3.14 | 43 |
| t3a.medium | 60% | 4 | 3.19 | 44 |
| t3a.medium | 40% | 4 | 3.56 | 49 |
| t3a.medium | 20% | 4 | 3.61 | 50 |
| t3a.2xlarge | n/a | 32 | 7.21 | 0 |

The 20 and 40% clusters and the 60 and 80% clusters started the same amount of servers as each other throughout the day.
So we can compare their costs to analyze cost-efficiencies in the second stage.
With differences of under 1% compared to the `t3.2xlarge` the cost savings we can make from this stage are not that significant.

Comparing the difference between the two pairs we can see that costs jump from 44 to 49%.
Therefore the final stage where there is an extra server sitting idle until end-of-day has a much larger impact.

So raising the scale threshold does have a significant impact when no extra server is added at market-close.
Choosing whether to do so will still be dependant on the needs of each system as a 5% decrease in costs may not be worth the risk of falling behind the tickerplant.


### Taking it further

#### Turning the cluster off

The saving estimates in the previous sections could be taken a step further with scheduled scaling.
For instance when the RDBs are not in use we could scale the cluster down to zero, effectively turning off the RDB.
Saturdays and Sundays are a prime example of when this could be useful, but it could also be extended to after end-of-day.

If data only starts coming into the RDB at around 07:00 when markets open there is no point having a server up.
So we could schedule the RDBs to turn down to zero at end-of-day, we then have a few options on when to scale back out.

- Schedule the ASG to scale out at 05:30 before the market opens.
    * Data will not be available until then if it starts to come in before.
- Monitor the tickerplant for the first message and scale out when it is received.
    * Data will not be available until the RDB comes up and recovers from the tickerplant log.
    * Will not be much data to recover.
- Scale out when the first query is run.
    * Useful because data is not needed until it is queried.
    * RDBs may come up before there is any data.
    * A large amount of data may need to be recovered if queries start to come in later in the day.

#### Intra-day write-down

The least complex way to run this solution would be in tandem with a write-down database (WDB) process.
The RDBs will not have to save down to disk at end-of-day, so scaling in will be quicker and more importantly, complexity will be greatly reduced.
If they were to write down at end-of-day a separate process would be needed to coordinate the writes of all the RDBs and then sort and part the data.

An elastic file system would also be needed for the multiple RDB servers to write to the HDB.
This may cause issues on AWS in particular as its EFS uses burst credits to distribute read and write throughput.
These are accumulated over time but may be exhausted if all of the day's data is written to disk in a short period of time.
Provisioned throughput could be used but it can be quite expensive especially if we are only writing to disk at end-of-day.

As the cluster will most likely be deployed alongside a WDB process an intra-day write-down solution could also be incorporated.
If we were to right down to disk every hour, we could also scale in the number of RDBs in the cluster every hour by calling `.sub.clear` with the intra-day write time.

Options for how to set up an intra-day write-down solution have been discussed in a previous Whitepaper by Colm McCarthy, [Intraday writedown solutions](https://code.kx.com/v2/wp/intraday-writedown).



## Conclusion

This paper has presented a solution for a scalable real-time database cluster.
The simulations carried out showed that savings of up to 50% could be made.
These savings along with the increased availability of the cluster could make holding a whole day's data in memory more feasible for our kdb+ databases.

If not, the cluster can easily be used alongside an intra-day write-down process.
If an intra-day write is incorporated in a system it is usually one that needs to keep memory usage low.
The scalability of the cluster can guard against large spikes in data intra-day crippling the system.
Used in this way very small instances could be used to reduce costs.

The `.u.asg` functionality in the tickerplant also gives the opportunity to run multiple clusters at different levels of risk.
Highly important data can be placed in a cluster with a low scale threshold or larger instance size.
If the data is less important smaller instances and higher scale thresholds can be used to reduce costs.

## Author
TODO

## Appendix


### 1. Cloudformation template

```yaml
Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
      - Label:
          default: "Amazon EC2 Configuration"
        Parameters:
          - AMI
          - SSHKEY
          - TICKINSTANCETYPE
      - Label:
          default: "Real-time Database Cluster Configuration"
        Parameters:
          - RDBINSTANCETYPE
          - SCALETHRESHOLD
          - ROLLTHRESHOLD
      - Label:
          default: "General Configuration"
        Parameters:
          - SUBNETID
          - VPCID

    ParameterLabels:
      AMI:
        default: "AMI Id"
      SSHKEY:
        default: "SSH Key"
      TICKINSTANCETYPE:
        default: "tickerplant Instance Type"
      RDBINSTANCETYPE:
        default: "RDB Instance Type"
      SCALETHRESHOLD:
        default: "Scale Threshold"
      ROLLTHRESHOLD:
        default: "Roll Threshold"
      SUBNETID:
        default: "Subnet Id"
      VPCID:
        default: "VPC Id"

Parameters:
  AMI:
    Type: AWS::EC2::Image::Id
    Description: "Choose the AMI to use for the EC2 Instances"
  SSHKEY:
    Type: AWS::EC2::KeyPair::KeyName
    Description: "Choose the ssh key that will be used to log on to the EC2 instances"
  TICKINSTANCETYPE:
    Type: String
    ConstraintDescription: "Must be a valid EC2 Instance Type"
    Description: "Choose the tickerplant's EC2 Instance Type"
  RDBINSTANCETYPE:
    Type: String
    ConstraintDescription: "Must be a valid EC2 Instance Type"
    Description: "Choose the RDB Cluster's EC2 Instance Type"
  SCALETHRESHOLD:
    Type: Number
    Description: "Choose the Memory Utilisation Percentage to scale up the Cluster"
    MinValue: 0
    MaxValue: 100
  ROLLTHRESHOLD:
    Type: Number
    Description: "Choose the Max Memory Utilisation Percentage for each RDB in the Cluster"
    MinValue: 0
    MaxValue: 100
  SUBNETID:
    Type: AWS::EC2::Subnet::Id
    Description: "Which Subnet should the EC2 Instances be deployed into"
  VPCID:
    Type: AWS::EC2::VPC::Id
    Description: "Which VPC should the EC2 Instances be deployed into"

Mappings:
  Constants:
    UserData:
      Bootstrap: |
        #!/bin/bash -x
        bash -x /opt/rdb-autoscaling/aws/app-userdata.sh

Resources:

  IAMRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - ec2.amazonaws.com
            Action:
              - 'sts:AssumeRole'
      Description: 'IAMRole for the EC2 Instances in the Stack'
      Policies:
        - PolicyName: !Sub '${AWS::StackName}.iam.policy'
          PolicyDocument:
            Version: 2012-10-17
            Statement:
              - Effect: Allow
                Action:
                  - autoscaling:DescribeAutoScalingGroups
                  - autoscaling:DescribeAutoScalingInstances
                  - autoscaling:SetDesiredCapacity
                  - autoscaling:TerminateInstanceInAutoScalingGroup
                  - cloudwatch:PutMetricData
                  - ec2:CreateImage
                  - ec2:CreateTags
                  - ec2:DeleteTags
                  - ec2:DescribeAddresses
                  - ec2:DescribeInstances
                  - ec2:DescribeTags
                  - elasticfilesystem:ClientMount
                  - elasticfilesystem:ClientRootAccess
                  - elasticfilesystem:ClientWrite
                Resource: "*"
      RoleName: !Sub '${AWS::StackName}.iam.role'

  IAMInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Path: /
      Roles:
        - !Ref IAMRole

  EfsSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: 'Security Group to allow EFS to be mounted by EC2 Instances'
      GroupName: !Sub '${AWS::Region}.${AWS::StackName}.efs-sg'
      SecurityGroupIngress:
        - FromPort: 2049
          IpProtocol: tcp
          ToPort: 2049
          SourceSecurityGroupId: !Ref EC2SecurityGroup
      VpcId: !Ref VPCID

  EC2SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: 'Security Group to allow SSH and TCP access for EC2 servers'
      GroupName: !Sub '${AWS::Region}.${AWS::StackName}.ec2-sg'
      SecurityGroupIngress:
        - CidrIp: 0.0.0.0/0
          FromPort: 22
          IpProtocol: tcp
          ToPort: 22
      VpcId: !Ref VPCID

  EC2SecurityGroupTcpIngress:
    Type: AWS::EC2::SecurityGroupIngress
    DependsOn: EC2SecurityGroup
    Properties:
      GroupId: !Ref EC2SecurityGroup
      FromPort: 5010
      IpProtocol: tcp
      ToPort: 5020
      SourceSecurityGroupId: !Ref EC2SecurityGroup

  EfsFileSystem:
    Type: AWS::EFS::FileSystem
    Properties:
      Encrypted: False
      FileSystemTags:
        - Key: Name
          Value: !Sub '${AWS::Region}-${AWS::StackName}-efs'
      PerformanceMode: generalPurpose
      ThroughputMode: bursting
  EfsMountTarget:
    Type: AWS::EFS::MountTarget
    Properties:
      FileSystemId: !Ref EfsFileSystem
      SecurityGroups:
        - !Ref EfsSecurityGroup
      SubnetId: !Ref SUBNETID

  EC2LaunchTemplate:
    Type: 'AWS::EC2::LaunchTemplate'
    Properties:
      LaunchTemplateData:
        BlockDeviceMappings:
            - DeviceName: /dev/xvda
              Ebs:
                VolumeSize: 8
        IamInstanceProfile:
          Arn: !GetAtt IAMInstanceProfile.Arn
        ImageId: !Ref AMI
        KeyName: !Ref SSHKEY
        SecurityGroupIds:
          - !Ref EC2SecurityGroup
        UserData:
          Fn::Base64:
            !FindInMap [ Constants, UserData, Bootstrap ]
      LaunchTemplateName: !Sub '${AWS::Region}.ec2-launch-template.${AWS::StackName}'

  TickASG:
    Type: 'AWS::AutoScaling::AutoScalingGroup'
    Properties:
      AutoScalingGroupName: !Sub '${AWS::Region}.ec2-asg.${AWS::StackName}-tick-asg'
      Cooldown: 300
      DesiredCapacity: 1
      HealthCheckGracePeriod: 60
      HealthCheckType: EC2
      MaxSize: 1
      MinSize: 0
      MixedInstancesPolicy:
        LaunchTemplate:
          LaunchTemplateSpecification:
            LaunchTemplateId: !Ref EC2LaunchTemplate
            Version: 1
          Overrides:
            - InstanceType: !Ref TICKINSTANCETYPE
      Tags:
        - Key: APP
          PropagateAtLaunch: True
          Value: tick-asg
        - Key: EFS
          PropagateAtLaunch: True
          Value: !GetAtt EfsMountTarget.IpAddress
        - Key: Name
          PropagateAtLaunch: True
          Value: !Sub '${AWS::Region}.ec2-instance.${AWS::StackName}-tick-asg'
      VPCZoneIdentifier:
        - !Ref SUBNETID

  RdbASG:
    Type: 'AWS::AutoScaling::AutoScalingGroup'
    DependsOn: [ TickASG ]
    Properties:
      AutoScalingGroupName: !Sub '${AWS::Region}.ec2-asg.${AWS::StackName}-r-asg'
      Cooldown: 300
      DesiredCapacity: 1
      HealthCheckGracePeriod: 60
      HealthCheckType: EC2
      MaxSize: 50
      MinSize: 0
      MixedInstancesPolicy:
        LaunchTemplate:
          LaunchTemplateSpecification:
            LaunchTemplateId: !Ref EC2LaunchTemplate
            Version: 1
          Overrides:
            - InstanceType: !Ref RDBINSTANCETYPE
      Tags:
        - Key: APP
          PropagateAtLaunch: True
          Value: r-asg
        - Key: EFS
          PropagateAtLaunch: True
          Value: !GetAtt EfsMountTarget.IpAddress
        - Key: Name
          PropagateAtLaunch: True
          Value: !Sub '${AWS::Region}.ec2-instance.${AWS::StackName}-r-asg'
        - Key: SCALETHRESHOLD
          PropagateAtLaunch: True
          Value: !Ref SCALETHRESHOLD
        - Key: ROLLTHRESHOLD
          PropagateAtLaunch: True
          Value: !Ref ROLLTHRESHOLD
      VPCZoneIdentifier:
        - !Ref SUBNETID
```


### 2. Cloudwatch metric commands

#### bash

```bash
aws cloudwatch put-metric-data --namespace RdbCluster \
    --dimensions AutoScalingGroupName=rdb-asg-1234ABCDE,InstanceId=i-1234567890abcdef
    --metric-name MemoryUsage --unit Bytes --value 1000
```

#### python

```python
from boto3 import client
from datetime import datetime


def put_metric_data(namespace, asg_name, instance_id, name, unit, value):
    """
    Send Metric Data for an EC2 Instance in an AutoScaling group to Cloudwatch
    """
    cloudwatch = client('cloudwatch')
    # build the metric data dictionary
    data = {
        'MetricName': name,
        'Dimensions': [
            {
                'Name': 'AutoScalingGroupName',
                'Value': asg_name
            },
            {
                'Name': 'InstanceId',
                'Value': instance_id
            },
        ],
        'Timestamp': datetime.now(),
        'Value': value,
        'Unit': unit
    }
    # send the data to aws
    cloudwatch.put_metric_data(Namespace=namespace,
                               MetricData=[data])

put_metric_data('RdbCluster', 'rdb-asg-1234ABCDE', 'i-1234567890abcdef', 'MemoryUsage', 'bytes', 1000)
```


### 3. Auto Scaling group commands

#### bash


```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name rdb-asg-1234ABCD

aws autoscaling set-desired-capacity --auto-scaling-group-name rdb-asg-1234ABCD --desired-capacity 2

aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-1234567890abcdef --should-decrement-desired-capacity
```

#### python

```python
import boto3


def get_metadata(asg_name):
    """
    Get meta data of an autoscaling group
    """
    asg = boto3.client('autoscaling')
    res = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
    return res['AutoScalingGroups'][0]


def get_desired_capacity(asg_name):
    """
    Find the current DesiredCapacity of an ASG
    """
    res = get_metadata(asg_name)
    return res['DesiredCapacity']


def set_desired_capacity(asg_name, desired_capacity):
    """
    Set the DesiredCapacity of an ASG
    Instances will either be terminated or launched once this is done
    """
    asg = boto3.client('autoscaling')
    res = asg.set_desired_capacity(AutoScalingGroupName=asg_name,
                                   DesiredCapacity=desired_capacity,
                                   HonorCooldown=False)
    return res


def increment_desired_capacity(asg_name):
    """
    Increase the DesiredCapacity of the ASG by 1
    """
    current = get_desired_capacity(asg_name)
    res = set_desired_capacity(asg_name, current + 1)
    return res


def terminate_instance_from_asg(instance_id):
    """
    Terminate the ec2 instance and reduce the DesiredCapacity
    """
    asg = boto3.client('autoscaling')
    res = asg.terminate_instance_in_auto_scaling_group(
        InstanceId=instance_id,
        ShouldDecrementDesiredCapacity=True
        )
    return res
```

