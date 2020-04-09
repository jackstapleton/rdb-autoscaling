# RDB Autoscaling

## Introduction

## Autoscaling

### Auto Scaling the RDBs

There a two ways we could scale the number of instances in our RDB Auto Scaling Group.

1. Cloudwatch Metrics
2. Manual Scaling

#### Cloudwatch Metrics

We could allow the Auto Scaling group to do the scaling based on a Cloudwatch Metric, say memory usage or row counts.

This is fine for when we need to scale out, as AWS will just start a new server when the metric is reached.
However, for scaling in it does not really suit our use case.

When scaling in, AWS will choose which instance to terminate based on certain criteria, e.g., instance count per Availability Zone, time to the next next billing hour.
You are able to replace the default behaviour with other options like `OldestInstance`, `NewestInstance` etc.
However, if after all the criteria have been evaluated there are still multiple instances to choose from, AWS will pick one at random.

Under no circumstance do we want AWS to terminate an instance of an RDB process which is still holding today's data.
So we will need to keep control of the Auto Scaling group's `Desired Capacity` within the application.

#### Manual Scaling

To manually scale our cluster we will use the AWS command line interface (cli).
Specifically the `aws autoscaling` cli.

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name rdb-autoscaling-group

aws autoscaling set-desired-capacity --auto-scaling-group-name rdb-autoscaling-group --desired-capacity 2

aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-1234567890abcdef --should-decrement-desired-capacity
```

As these are unix commands we can run them in kdb+ using `system`.
The results of these functions will be returned as `json` so we will be able to use `.j.k` to parse them into dictionaries.

### Auto Scaling in Q

The `asg/util.q` file holds a number of API functions to interact with the `aws autoscaling` cli.

We will use the cli for two purposes:

1. Increase the `DesiredCapacity` by one as the RDB is filling up with data.
2. Terminate a specific server from the Auto Scaling group, while also decreasing the `DesiredCapacity` by one.

Calls using the cli can sometimes timeout if AWS is under load, so it is worth wrapping any system calls using the cli in a retry loop.

```q
.util.sys.runWithRetry:{[cmd]
    n: 0;
    while[not last res:.util.sys.runSafe cmd;
            if[10 < n+: 1; 'res 0]
            ];
    res 0
 };

.util.sys.runSafe: @[{(system x;1b)};;{(x;0b)}];
```

To scale out by one we will need to use the `decribe-auto-scaling-group` option.
This will give us the current `DesiredCapacity`, we can then use the `set-desired-capacity` option to increase it by one.

```q
.util.aws.scale:{[groupName]
    needed: 1 + .util.aws.getDesiredCapacity groupName;
    .util.aws.setDesiredCapacity[groupName;needed];
    while[not needed = .util.aws.getDesiredCapacity groupName;
            .util.aws.setDesiredCapacity[groupName;needed] ];
 };

.util.aws.getDesiredCapacity:{[groupName]
    first .util.aws.describeASG[groupName]`DesiredCapacity
 };

/ aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name rdb-autoscaling-group
.util.aws.describeASG:{[groupName]
    res: .util.sys.runWithRetry "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name ",groupName;
    res: flip (.j.k "\n" sv res)`AutoScalingGroups;
    if[() ~ res; 'groupName," is not an autoscaling group"];
    res
 };

/ aws autoscaling set-desired-capacity --auto-scaling-group-name rdb-autoscaling-group --desired-capacity n
.util.aws.setDesiredCapacity:{[groupName;n]
    .util.sys.runWithRetry "aws autoscaling set-desired-capacity --auto-scaling-group-name ",groupName," --desired-capacity ",string n
 };
```

To terminate the server we will use the `terminate-instance-in-auto-scaling-group` option.
We will also specify that we want to reduce the `DesiredCapacity` with the `--should-decrement-desired-capacity` flag.

```q
/ aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-1234567890abcdef0 --should-decrement-desired-capacity
.util.aws.terminate:{[instanceId]
    .j.k "\n" sv .util.sys.runWithRetry "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"
 }
```

These utility functions will be used by the RDB processes.
So the RDBs will be the ones to manage the Auto Scaling in our application.

## Real-time Data Cluster

### Overview

- Real-time data will be shared between instances in a cluster.
- The number of instances will increase throughout the day as more data is added to the cluster.
- At the end of the day the day's data will be flushed, and the cluster will scale in.

The code to coordinate the RDBs queue is in the `.u.asg` namespace.
Its functions act as a wrapper around kdb-tick's `.u` functionality.
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

If the RDB comes up too early, the Tickerplant must add it to the queue, while remembering the RDBs handle, and the tables it is subscribing for.
If it does this, it can add it to `.u.w` when it needs to.

If the RDB does not come up in time, the Tickerplant must remember the last `upd` message it sent to the previous RDB.
When the RDB eventually comes up it can use this to recover the data from the Tickerplant's log file.
This will prevent any gaps in the data.

The Tickerplant will store these details in `.u.asg.tab`.

#### `.u.asg.tab`

When it is time to roll to the next subscriber the Tickerplant will query this table for the next RDB in the queue.
It will take the handle, tables and symbols and add them to `.u.w`.
kdb-ticks functionality will then take over and start publishing to the new RDB.

```q
/ table used to handle subscriptions
/   time   - time the subscriber was added
/   handle - handle of the subscriber
/   tabs   - tables the subscriber has subscribed for
/   syms   - syms the subscriber has subscribed for
/   queue  - queue the subscriber is a part of
/   live   - time the tickerplant started publishing to the subscriber
/   rolled - time the subscriber unsubscribed
/   lastI  - last message sent to the subscriber

.u.asg.tab: flip `time`handle`tabs`syms`queue`live`rolled`lastI!();
`.u.asg.tab upsert (0Np;0Ni;();();`;0Np;0Np;0N);
```

### Adding Subscribers

To be added to `.u.asg.tab`, a subscriber must call `.u.asg.sub`.

One limitation of `.u.asg.sub` is that the Tickerplant now kicks off the replay of the log on the RDB.
If there is no RDB already in the queue, the Tickerplant will make it the live subscriber, so the replay will be kicked off immediately.
This means the RDBs in the cluster cannot make multiple `.u.asg.sub` calls.

```q
/ t - A list of tables (or \` for all).
/ s - Lists of symbol lists to subscribe to for the tables.
/ q - The name of the queue to be added to.

.u.asg.sub:{[t;s;q]
    if[-11h = type t;
            t: enlist t;
            s: enlist s];

    if[not (=) . count each (t;s);
            '"Count of table and symbol lists must match" ];

    if[not all missing: t in .u.t,`;
            '.Q.s1[t where not missing]," not available" ];

    `.u.asg.tab upsert (.z.p; .z.w; t; s; q; 0b; 0b; 0N);

    if[not count select from .u.asg.tab where not null live, null rolled, queue = q;
            .u.asg.add[t;s;.z.w]];
 };
```

First there are some checks made on the arguments.
- Ensure `t` and `s` are enlisted.
- Check the count of `t` and `s` match.
- Check that all tables in `t` are available for subscription.

A record is than added to `.u.asg.tab` for the subscriber.

Finally `.u.asg.tab` is checked to see if there is another RDB in the queue.
If the queue is empty the Tickerplant will immediately make this RDB the *live* subscriber.

### The Live Subscriber

We will use the term *live* to describe the RDBs that are currently in `.u.w`.
When in `.u.w` the Tickerplant will be publishing data to them.

To make an RDB the *live* the subscriber the Tickerplant will call `.u.asg.add`.

There are two instances when this is called:
1. When an RDB subscribes to a queue with no *live* subscriber.
2. When the Tickerplant is rolling subscribers.

```q
/ t - List of tables the RDB wants to subscribe to.
/ s - Symbol lists the RDB wants to subscribe to.
/ h - The handle of the RDB.

.u.asg.add:{[t;s;h]
    update live:.z.p from `.u.asg.tab where handle = h;
    schemas: .u.subInner[;;h] .' flip (t;s);
    neg[h] (`.sub.rep; schemas; .u.L; (max 0^ exec lastI from .u.asg.tab; .u.i));
 };
```

- First the RDB is marked as the *live* subscriber in `.u.asg.tab`.
- `.u.subInner` is then used to add the handle to `.u.w` and get the schemas needed by the RDB.
- The last `upd` processed by the RDBs queue is found.
- `sub.rep` is then called on the RDB.
    * The schemas, log file and log window are sent as arguments.

### Becoming the Live Subscriber

When the Tickerplant makes an RDB the *live* subscriber it will call `.sub.rep` to initialise it.

```q
/ schemas   - table names and schemas of subscription tables
/ tplog     - file path of the tickerplant log
/ logWindow - start and end of the window needed in the log, (start;end)

.sub.rep:{[schemas;tplog;logWindow]
    (.[;();:;].) each schemas;
    .sub.start: logWindow 0;
    `upd set .sub.replayUpd;
    -11!(logWindow 1;tplog);
    `upd set .sub.upd;
    .z.ts: .sub.monitorMemory;
    system "t 5000";
    .sub.live: 1b;
 };
```

Like in `tick/r.q` the RDBs will set the the tables' schemas and replay the Tickerplant's log.

#### Replaying the Tickerplant Log

In kdb-tick `.u.i` will be sent to the RDB.
The RDB will then replay that many `upd` messages from the log.
As it replays it inserts every row of data in the `upd` messages into the tables.

We do not want keep everything in the log as other RDB's may be holding some of the day's data.
To avoid holding duplicate data, `logWindow` is passed as down from the Tickerplant.

`logWindow` is a list of two integers:
1. The last `upd` message processed by the other RDBs.
2. The last `upd` processed by the Tickerplant, `.u.i`.

- `.sub.start` is set to the first element of `logWindow`.
-  `upd` is set to `.sub.replayUpd`.
- The Tickerplant log is replayed until the second element in `logWindow` (`.u.i`).

`.sub.replayUpd` is then called for every `upd` message.
It increments `.sub.i` for every `upd` message until it is greater than `.sub.start`.
From that point on it calls `.sub.upd` to insert the data.

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

One other function of `.sub.replayUpd` is to monitor the memory of the server.
It starts to do this as it adds data to the tables.
This will protect the RDB in the case where there is too much data in the log to replay.
In this case the RDB will unsubscribe from the Tickerplant and another RDB will continue the replay.

After the log has been replayed `upd` is set to `.sub.upd`.
This function will continue to increment `.sub.i` for every `upd` the RDB receives.

### Monitoring RDB Server Memory

The RDB monitors the memory of its server for two reasons:

1. Tell the Auto Scaling group to scale.
2. Stop subscribing from the Tickerplant.

The last function of `.sub.rep` is to start the monitoring process.

1. `.z.ts` is set to `.sub.monitorMemory`.
2. `\t` is set to 5000, so the timer will run every 5 seconds.

```q
.sub.monitorMemory:{[]
    if[not .sub.scaled;
        if[.util.getMemUsage[] > .sub.scaleThreshold;
                -1 "Scaling ", .aws.groupName;
                .util.aws.scale .aws.groupName;
                .sub.scaled: 1b;
                ];
        :(::);
        ];
    if[not .sub.rolled;
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
From tahat point The RDB will no longer receive data from the Tickerplant, but it will be available to query.

```q
.sub.roll:{[]
    .sub.live: 0b;
    .sub.rolled: 1b;
    `upd set {[x;y] (::)};
    .sub.TP ({.u.asg.roll[.z.w;x]}; .sub.i);
 };
```

`.sub.roll` marks `.sub.live` as false and `.sub.rolled` as true and `upd` is set to `{[x;y] (::)}` so that no further `upd` messages are processed.
It will also call `.u.asg.roll` on the Tickerplant, using its own handle and `.sub.i` as arguments.

```q
/ h    - handle of the RDB
/ subI - last processed upd message

.u.asg.roll:{[h;subI]
    cfg: exec from .u.asg.tab where handle = h;
    update rolled:.z.p, lastI:subI from `.u.asg.tab where handle = h;
    .u.del[;h] each .u.t;
    if[count queue: select from .u.asg.tab where null live, null rolled, queue = cfg`queue;
            .u.asg.add . first[queue]`tabs`syms`handle];
 };
```

The Tickerplant marks the RDB that calls this function as *rolled* and `.sub.i` stored in the `lastI` column.
It then uses kdb-tick's `.u.del` to delete the RDB's handle from `.u.w`.

Finally the Tickerplant searches `.u.asg.tab` for the next RDB in the queue.
If there is one it calls `.u.asg.add` making it the new *live* subscriber, and the cycle continues.

If there is no RDB ready in the queue, the next RDB to come up will immediately be added to `.u.w` and `.sub.i` will be used to recover from the Tickerplant log.


### End of Day

So throughout the day the RDB cluster will grow in size as the RDBs start, subscribe, fill and roll.

In the majority of systems, when end of day is called the data will be written to disk and flushed from the RDB.
In our case when we do this the *rolled* RDB's will be sitting idle with no data.
So we will also want the cluster to scale in by terminating these servers.

When end of data occurs the Tickerplant will call `.u.end`.
`.u.end` will call `.u.asg.end` to call `.u.end` on all rolled subscribers and deletes their records from `.u.asg.tab`.

```q
.u.asg.end:{[]
    rolled: exec handle from .u.asg.tab where not null handle, not null rolled;
    rolled @\: (`.u.end; .u.d);
    delete from `.u.asg.tab where not null rolled;
 };
```

`.u.end` on the RDBs will call `.sub.clear` to flush all T+1 data and terminate the rolled servers if they have no data left.

```q
.u.end: {[dt] .sub.clear dt+1};

.sub.clear:{[tm]
    ![;enlist(<;`time;tm);0b;`$()] each tables[];
    if[.sub.rolled;
        if[not max count each get each tables[];
                .util.aws.terminate .aws.instanceId;
                ];
        ];
 };
```

- All of the previous day's data will be deleted each table.
- If the RDB has been rolled and has no data left in its tables it will call `.util.aws.terminate`.
- `.util.aws.terminate` will both terminate the instnace and reduce the `DesiredCapacity` by one.

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

`tickasg.q` begins by loads both `tick.q` and `asg/u.q` loading in `.u` and `.u.asg`.
`.u.tick` is ran in `tick.q` so the Tickerplant is started.

`.z.pc` and `.u.end` are then overwritten to use both the `.u` and `.u.asg` versions.

```q
.u.asg.zpc:{[h]
    if[not null first exec live from .u.asg.tab where handle = h;
            .u.asg.roll[h;0]];
    update handle:0Ni from `.u.asg.tab where handle = h;
 };
```

If the disconnecting RDB is the live subscriber the Tickerplant calls `.u.asg.roll`.
`.u.asg.zpc` updates the handle column in `.u.asg.tab` to be null for the disconnected RDB.

There are also some minor changes made to `.u.add` and `.u.sub` in `asg/u.q`.

#### Changes to `.u`

Even with these changes, `.u` will still work as normal, so `tick/r.q` can still be used.

The main change is needed because `.z.w` cannot be used in `.u.sub` or `.u.add` anymore.
When there is a queue of RDBs `.u.sub` will not be called in the RDBs initial subscription call.
It will only be called when the Tickerplant rolls the live subscriber, or when the live subscriber disconnects.
In either scenario `.z.w` will not be the handle of the RDB we want to start publishing to.

To remediate this `.u.add` has been changed to take a handle as a third parameter instead of using `.z.w`.
The same change could not be made to `.u.sub` as it is the entry function for kdb-ticks `tick/r.q`.
To keep `tick/r.q` working `.u.subInner` has been added, it is a copy of `.u.sub` but it does take a handle as a third parameter, and it now passes that handle into `.u.add`.
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

- .aws.instanceId - instance id of its EC2 instance.
- .aws.groupName - name of its Auto Scaling group.
- .sub.scaleThreshold - memory percentage threshold to scale out.
- .sub.rollThreshold - memory percentage threshold to unsubscribe.
- .sub.live - whether Tickerplant is currently it sending data.
- .sub.scaled - whether it has launched a new instance.
- .sub.rolled - whether it has unsubscribed.
- .sub.i - count of `upd` messages queue has processed.

## AWS Setup

#### Amazon Machine Image (AMI)

To set this all up on AWS we will first need an Amazon Machine Image (AMI).
For this we will start an EC2 instance, install kdb+, and deploy our code to the server.
We will then create an Amazon Machine Image (AMI) using the amazon cli.

```bash
INSTANCEID=$(ec2-metadata -i | cut -d ' ' -f 2)
AMINANME=kdb-rdb-autoscaling-ami-$(date +%Y%m%dD%H%M%S)
aws ec2 create-image --instance-id $INSTANCEID --name $AMINAME
```

An AMI is a template EC2 uses to start instances.
Creating one with our code and software means we can start multiple servers with identical software, this will ensure consistency across our Stack.

#### Cloudformation

Next we will launch a Stack using AWS Cloudformation.
Cloudformation allows us to use a json or yaml file to provision AWS resources.

Our Stack will consist of:

- AWS ElasticFileSystem (EFS).
- EFS Mount Target.
- Tickerplant Launch Template
- Tickerplant Auto Scaling group
- RDB Launch Template
- RDB Auto Scaling group

##### AWS ElasticFileSystem (EFS)

EFS is a Network File System (NFS) which any EC2 instance can mount.
This solves the first problem with kdb-tick when the Tickerplant and RDB are on different servers.
Without a common file system the RDB would not be able to replay the Tickerplant's log file on start up.
An example of how to deploy an EFS file system in a yaml Cloudformation template is below.

```yaml
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
      SecurityGroups: !Ref SECURITYGROUPIDS
      SubnetId: !Ref SUBNETID
```

The `EfsMountTarget` is an NFS endpoint.
It will allow any EC2 instances in the same Availability Zone to mount the `EfsFileSystem`.

Another way to solve the tickerplant log problem would be to have a log streamer process running on the Tickerplant server.
This process would replay the log for the RDB using `-11!`, and send the `upd` messages to the RDB over an IPC handle.

```
.u.stream: {[tplog;start;end]
    .u.start: start;
    -11!(tplog;end);
    delete start from `.u;
 };

upd:{
    if[.u.start < .u.i+:1;
            neg[.z.w] @ (`upd;x;y);
            neg[.z.w][]]
 }
```

##### Auto Scaling Groups

An Auto Scaling group can use a Launch Template or Launch Configuration to launch EC2 instances.
It will maintain a set number of instances, this number is specified by its `DesiredCapacity` metric.
If any of its instances go down, the group will launch a new one to replace it.

In our case we will use a Launch Template, it will use the AMI we created with our code.
It will also specify other details like the `InstaceType` and the `UserData` we want the server to run when it is booted up.
The Tickerplants Launch Template is outlined below.

```yaml
  TickLaunchTemplate:
    Type: 'AWS::EC2::LaunchTemplate'
    Properties:
      LaunchTemplateData:
        BlockDeviceMappings:
            - DeviceName: /dev/xvda
              Ebs:
                VolumeSize: 8
        IamInstanceProfile:
          Arn: !Ref IAMINSTANCEPROFILE
        ImageId: !Ref AMI
        InstanceType: t2.small
        KeyName: !Ref SSHKEY
        SecurityGroupIds: !Ref SECURITYGROUPIDS
        TagSpecifications:
          - ResourceType: instance
            Tags:
            - Key: Name
              Value: !Sub '${AWS::Region}.ec2-instance.${AWS::StackName}.tick-asg'
        UserData:
          Fn::Base64: |
            #!/bin/bash
            bash /opt/rdb-autoscaling/aws/ec2-userdata.sh
      LaunchTemplateName: !Sub '${AWS::Region}-${AWS::StackName}-tick-asg-launch-template'
```

The first Auto Scaling group we deploy will be for the Tickerplant.
There will only ever be one instance for the Tickerplant, so we are putting it in an Auto Scaling group for recovery purposes.
If it goes down the Auto Scaling group will automatically start another one.
So its `MinSize`, `MinSize` and `DesiredCapacity` will all be set to 1.
Setting the `DesiredCapacity` to 1 will mean the Auto Scaling group will immediately launch an instance when it is created.

```yaml
  TickASG:
    Type: 'AWS::AutoScaling::AutoScalingGroup'
    Properties:
      Cooldown: 300
      DesiredCapacity: 1
      HealthCheckGracePeriod: 60
      HealthCheckType: EC2
      LaunchTemplate:
        LaunchTemplateId: !Ref TickLaunchTemplate
        Version: 1
      MaxSize: 1
      MinSize: 1
      Tags:
        - Key: APP
          PropagateAtLaunch: True
          Value: tick-asg
        - Key: EFS
          PropagateAtLaunch: True
          Value: !GetAtt EfsMountTarget.IpAddress
      VPCZoneIdentifier:
        - !Ref SUBNETID
```

The second group will be for the RDBs.
These servers we will actually scale in and out.
So the `MinSize`, `MinSize` and `DesiredCapacity` will be set to 0, 20 and 1 respectively.

```yaml
  RdbASG:
    Type: 'AWS::AutoScaling::AutoScalingGroup'
    DependsOn: [ GatewayASG ]
    Properties:
      Cooldown: 300
      DesiredCapacity: 0
      HealthCheckGracePeriod: 60
      HealthCheckType: EC2
      LaunchTemplate:
        LaunchTemplateId: !Ref RdbLaunchTemplate
        Version: 1
      MaxSize: 20
      MinSize: 0
      Tags:
        - Key: APP
          PropagateAtLaunch: True
          Value: r-asg
        - Key: EFS
          PropagateAtLaunch: True
          Value: !GetAtt EfsMountTarget.IpAddress
      VPCZoneIdentifier:
        - !Ref SUBNETID

  RdbLaunchTemplate:
    Type: 'AWS::EC2::LaunchTemplate'
    Properties:
      LaunchTemplateData:
        BlockDeviceMappings:
            - DeviceName: /dev/xvda
              Ebs:
                VolumeSize: 8
        IamInstanceProfile:
          Arn: !Ref IAMINSTANCEPROFILE
        ImageId: !Ref AMI
        InstanceType: t2.small
        KeyName: !Ref SSHKEY
        SecurityGroupIds: !Ref SECURITYGROUPIDS
        TagSpecifications:
          - ResourceType: instance
            Tags:
            - Key: Name
              Value: !Sub '${AWS::Region}.ec2-instance.${AWS::StackName}.r-asg'
        UserData:
          Fn::Base64: |
            #!/bin/bash
            bash /opt/rdb-autoscaling/aws/ec2-userdata.sh
      LaunchTemplateName: !Sub '${AWS::Region}-${AWS::StackName}-r-asg-launch-template'
```


### Tickerplant







## Recovery

Code changes to replay logs.
Tickerplant logs will be on a different server.
Could avoid this if they are on EFS, so could run through the pros and cons of that.
RDBs must only replay a window of data from the logs as
Intraday write down solution


## Cost Analysis

Show cost differences of having one large box up all the time compared to increasing the number of small boxes throughout the day.


## Discuss the Risk

Adding complexity.
EC2 instance may not start fast enough.


## Conclusion

Run through the pros and cons of the solution in the paper.
Give examples of how to take the solution further.
Table, sym sharding etc.
More granular autoscaling.
Writing down intraday.


## Appendix


