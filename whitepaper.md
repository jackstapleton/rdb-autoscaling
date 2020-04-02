# RDB Autoscaling

## Introduction

## Autoscaling

## Real-time Data Cluster

- Real-time data will be shared between instances in a cluster.
- The number of instances will increase throughout the day as more data is added to the cluster.
- At the end of the day the day's data will be flushed, and the cluster will scale in.




### Scaling the Cluster

On a high level the scaling method is quite simple.

1. A single RDB instance is launched and subscribes to the Tickerplant.
3. When it fills up with data a second RDB will come up to take its place.
4. This cycle repeats throughout the day growing the cluster.
5. At end of day all but the latest RDB instances are shutdown.

### The Subscriber Queue

There is one issue with the solution outlined above.
An RDB will not come up at the exact moment it's predecessor unsubscribes.
So there are two scenarios that the Tickerplant must account for.

1. The new RDB comes up too early.
2. The new RDB does not come up in time.

If the RDB comes up too early, the Tickerplant must add it to the queue, while remembering the RDBs handle, and the tables it is subscribing for.
If it does this, it can add it to `.u.w` when it needs to.

If the RDB does not come up in time, the Tickerplant must remember the last `upd` message it sent to the previous RDB.
When the RDB eventually comes up it can use this to recover the data from the Tickerplant's log file.
This will prevent any gaps in the data.

#### `asg/u-asg.q`

The code to coordinate the RDBs queue is in the `.u.asg` namespace.
It's functions act as a wrapper around kdb-tick's `.u` functionality.
I.e., the functions will determine when to call `.u.sub` and `.u.del` in order to add and remove the subscriber from `.u.w`.

#### `.u.asg.tab`

The Tickerplant will keep track of the cluster's RDBs in `.u.asg.tab`.

```q
/ time   - time the subscriber was added.
/ handle - handle of the subscriber.
/ tabs   - tables the subscriber has subscribed for.
/ syms   - syms the subscriber has subscribed for.
/ queue  - queue the subscriber is a part of.
/ live   - whether the subscriber is currently being published to.
/ rolled - whether the subscriber has unsubscribed.
/ lastI  - last message sent to the subscriber.

.u.asg.tab: flip `time`handle`tabs`syms`queue`live`rolled`lastI!();
`.u.asg.tab upsert (0Np;0Ni;();();`;0b;0b;0N);
```

To be added to this table, a subscriber must call `.u.asg.sub`.

```q
/ t - A list of tables (or \` for all).
/ s - Lists of symbol lists to subscribe to for the tables.
/ p - The name of the queue to be added to.

.u.asg.sub:{[t;s;q]
    if[not (=) . count each (t;s);
            '"Count of table and symbol lists must match" ];

    if[not all missing: t in .u.t,`;
            '.Q.s1[t where not missing]," not available" ];

    `.u.asg.tab upsert (.z.p; .z.w; t; s; q; 0b; 0b; 0N);

    if[not count select from .u.asg.tab where live, queue = q;
            .u.asg.add[.z.w;t;s] ];
 };
```

There are some checks made on the arguments and then the subscriber is added to `.u.asg.tab`.
`.u.asg.tab` is checked to see if there is another RDB in the queue.
If the queue is empty the Tickerplant will immediately make this RDB the 'live' subscriber.

To do this `.u.asg.add` is called.

```q
.u.asg.add:{[t;s;h]
    update live:1b from `.u.asg.tab where handle = h;
    / add subscriber to .u.w
    schemas: $[-11h = type t;
                    enlist .u.subInner[t;s;h];
                    .u.subInner[;;h] .' flip (t;s)];

    startI: max 0^ exec lastI from .u.asg.tab;
    neg[h] (`.sub.rep; schemas; .u.d; .u.L; (startI;.u.i));
 };
```

`.u.asg.add` first marks the RDB as the 'live' subscriber for that queue.
It then calls `.u.subInner` to add the handle to `.u.w`.
This returns the schemas the RDB will set.
Next it finds the last `upd` message sent to the other subscribers in it's queue.
This will be used by the RDB when replaying the Tickerplant's log file.

One limitation of `.u.asg.sub` is that the Tickerplant now kicks off the replay of the log on the RDB.
If there is no RDB already in the queue, the Tickerplant will make it the live subscriber, so the replay will be kicked off immediately.
This means the RDB in the cluster cannot make multiple `.u.asg.sub` calls.

This is the reasoning behind sending lists of tables and symbol lists.
It also leads to the messy count and type checks in the two functions above.

```q
    / .u.asg.sub
    if[not (=) . count each (t;s);
        '"Count of table and symbol lists must match" ];

    / .u.asg.add
    schemas: $[-11h = type t;
                    enlist .u.subInner[t;s;h];
                    .u.subInner[;;h] .' flip (t;s)];
```

When an RDB has filled up with data it will unsubscribe and call `.u.asg.roll` on the Tickerplant.

```q
.u.asg.roll:{[h;subI]
    cfg: exec from .u.asg.tab where handle = h;
    / update .u.asg.tab
    update live:0b, rolled:1b, lastI:subI from `.u.asg.tab where handle = h;
    / remove handle h from .u.w
    .u.del[;h] each cfg`tabs;
    / add the next rdb in the que if there is one
    if[count queue: select from .u.asg.tab where not live, not rolled, queue = cfg`queue;
            .u.asg.add . first[queue]`tabs`syms`handle ];
 };
```

The subscriber is marked as 'rolled' and last `upd` message that RDB processed is stored in the lastI column.
`.u.del` is called to delete it's handle from `.u.w`.

Finally the Tickerplant searches `.u.asg.tab` for the next RDB in the queue.
If there is one it calls `.u.asg.add` and the cycle continues.
If not the next RDB that subscribes will immediately be added to `.u.w` and use lastI to recover from the Tickerplant log.

#### Auto Scaling the RDBs

There a few ways to manage the number of instances in our RDB Auto Scaling Group.

We could allow Auto Scaling group to do the scaling based on Cloudwatch Metrics, say memory usage or row counts.

This is fine for when we need to scale out, as AWS will just start a new server.
However, for scaling in it does not really suit our use case.

When scaling in, AWS will choose which instance to terminate based on certain criteria, e.g., instance count per Availability Zone, time to the next next billing hour.
You are able to replace the default behaviour with other options like `OldestInstance`, `NewestInstance` etc.
However, if after all the criteria have been evaluated there are still multiple instances to choose from, AWS will pick one at random.

Under no circumstance do we want AWS to terminate an instance of an RDB process which is still holding today's data.
So we will need to keep control of the Auto Scaling group's `Desired Capacity` within the application.

This can be done using the python's `boto3` library, or we can use the AWS command line interface (cli).
Specifically the `aws autoscaling` cli.

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name rdb-autoscaling-group

aws autoscaling set-desired-capacity --auto-scaling-group-name rdb-autoscaling-group --desired-capacity 2

aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-1234567890abcdef --should-decrement-desired-capacity
```

As these are unix commands we can run them in kdb+ using `system`, and we can use `.j.k` to parse the results as they will be in `json`.

##### asg/util.q

`asg/util.q` holds a number of api functions to interact with the `aws autoscaling` cli.

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
So RDBs themselves will be the ones to manage the Auto Scaling.

#### asg/sub.q

When the RDBs subscribe they will call `.u.asg.sub` on the Tickerplant.
The Tickerplant will then add them to the queue and when they become the live subscriber, it will asynchronously call `.sub.replay` on the RDB.

```q
.sub.rep:{[schemas;tplog;logWindow]
    (.[;();:;].) each schemas;

    .sub.live: 1b;
    .sub.start: logWindow 0;

    `upd set .sub.replayUpd;
    -11!(logWindow 1;tplog);

    `upd set .sub.upd;
 };
```

Like in `tick/r.q` the RDBs will set the schemas the Tickerplant passes down.
It will then set `.sub.live` to be true.

Then it will move on to replaying the Tickerplant's log.
As other RDBs may be holding the first portion of the log's data, not all `upd` messages in the log will be needed.

So the `logWindow` is passed down by the Tickerplant, telling the RDB where to both start and stop replaying data from the log.
`.sub.start` is taken from the first element of `logWindow` and is set as a global so it can be read within the function `upd`.

`upd` is set to `.sub.replayUpd`, this function counts the `upd` messages by incrementing `.sub.i`.
It only starts to insert data into the in memory tables when `.sub.i` becomes greater than `.sub.start`.

```q
.sub.replayUpd:{[t;x]
    if[.sub.i > .sub.start;
        if[not .sub.i mod 100; .sub.monitorMemory[]];
        .sub.upd[t;flip x];
        :(::);
        ];
    .sub.i+: 1;
 };
```

When it starts to add data to the table it also starts to monitor the memory of the server.
This will protect the RDB in the case where there is too much data in the log to replay.
If this occurs the RDB will unsubscribe from the Tickerplant and another will take it's place and continue the replay.

After the log has been replayed `upd` is set to `.sub.upd`.
This function will continue to increment `.sub.i` for every `upd` the RDB receives.

```q
.sub.upd: {.sub.i+: 1; x upsert y};
```

Once the process is live, `.z.ts` will be set to `.sub.monitorMemory`.

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
                .sub.unsub[];
                ];
        ];
 };
```

The process will repeatedly check it's memory usage until it reaches `.sub.scaleThreshold`.
Once that it is reached it will use `.util.aws.scale` to increment the Auto Scaling group's `DesiredCapacity`.
It will then set `.sub.scaled` to be true to ensure it does not scale the Auto Scaling group again.

The RDB will then start checking it's memory usage against `.sub.rollThreshold` to see if it needs to stop subscribing.
Ideally `.sub.scaleThreshold` and `.sub.rollThreshold` will be set far enough apart so that the new RDB has time to come up queue before `.sub.rollThreshold` is reached.
This will reduce the amount of `upd` messages the new RDB will have to replay.

When `.sub.rollThreshold` is reached the RDB will call `.sub.roll` on the Tickerplant.
This will make the Tickerplant roll to the next subscriber.

```q
.sub.roll:{[]
    .sub.TP ({.u.asg.roll[.z.w;x]}; .sub.i);
    .sub.live: 0b;
    .sub.rolled: 1b;
    `upd set .sub.disconnectUpd;
 };

.sub.disconnectUpd: {[t;x] (::)};
```

It passes `.sub.i` to the Tickerplant so it knows where to tell the next RDB to start replaying its log from.

It also marks `.sub.live` as false and `.sub.rolled` as true so it does try to not unsubscribe again.
`upd` is set to `.sub.disconnectedUpd` so that no further `upd` messages are processed.

The RDB will no longer receive any data from the Tickerplant, but it will be available to query.
At end of day it will still receive `.u.end` as in kdb-tick.
It will then call `.sub.clear`.

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

`.sub.clear` will first delete the previous data from each table.
If the RDB  is no longer the live subscriber it will check if any of the tables have any data left.
If not the RDB will make a call to the Auto Scaling group, to terminate it's own instance from the Auto Scaling group and decrease the `DesiredCapacity`.
So at end of day all old instances will be shut down.


#### tick-asg.q

```q
/ initialise kdb-tick
system "l tick.q"

/ load .u.asg code
/ rewrites .u.sub & .u.add to take .z.w as a parameter
system "l asg/u-asg.q"

/ rewrite .z.pc to run tick and asg .z.pc
.tick.zpc: .z.pc;
.z.pc: {.tick.zpc x; .u.asg.zpc x;};

/ rewrite .u.end to run tick and asg .z.pc
.tick.end: .u.end;
.u.end: {.tick.end x; .u.asg.end x;};
```

`tick-asg.q` begins by loading `tick.q` from kdb-tick, to initialise the Tickerplant.
It then loads in `asg/u-asg.q`, this script defines the functions used to coordinate the queue of auto scaling RDBs.
It also makes minor changes to the `tick/u.q` functions below:
- `.u.add`
- `.u.sub`
- `.z.pc`
- `.u.end`

##### Changes to kdb-tick

Even with the below changes, `.u` will still work as normal, so `tick/r.q` can still be used.

The main change is needed because `.z.w` cannot be used in `.u.sub` or `.u.add` anymore.
When the queue of RDBs develops `.u.sub` will not be called in the RDBs initial subscription call.
It will only be called when the Tickerplant rolls the live subscriber, or when the live subscriber disconnects.
In either scenario `.z.w` will not be the handle of the RDB we want to start publishing to.

To remediate this `.u.add` has been changed to take a handle as a third parameter instead of using `.z.w`.
The same change could not be made to `.u.sub` as it is the entry function for kdb-ticks `tick/r.q`.
To keep `tick/r.q` working `.u.subInner` has been added, it is a copy of `.u.sub` but it does take a handle as a third parameter, and it now passes that handle into `.u.add`.
`.u.sub` is now a projection of `.u.subInner`, it passes `.z.w` in as the third parameter.

```q
\d .u

// kdb-tick u.q //

add:{$[(count w x)>i:w[x;;0]?.z.w;.[`.u.w;(x;i;1);union;y];w[x],:enlist(.z.w;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}

sub:{if[x~`;:sub[;y]each t];if[not x in t;'x];del[x].z.w;add[x;y]}

// new versions //

/ use 'z' instead of .z.w
add:{$[(count w x)>i:w[x;;0]?z;.[`.u.w;(x;i;1);union;y];w[x],:enlist(z;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}

/ use 'z' instead of .z.w, and input as 3rd argument to .u.add
subInner:{if[x~`;:sub[;y]each t];if[not x in t;'x];del[x]z;add[x;y;z]}
sub:{subInner[x;y;.z.w]}

\d .
```

The only other two changes are to `.z.pc` and `.u.end`.
They have been changed to add the code needed for `.u.asg` in the event of a closed handle and end of day.

### AWS Setup

#### Amazon Machine Image (AMI)
To achieve this on AWS we will start an EC2 instance, install kdb+, and deploy our code to the server.
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
Cloudformation allows us to use a json or yaml file to provision resources.

Our Stack will consist of two Auto Scaling groups, and one AWS ElasticFileSystem (EFS).

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
TODO
add logstreamer code
```

##### Auto Scaling Groups

An Auto Scaling group can use a Launch Template or Launch Configuration to launch EC2 instances.
It will maintain a set number of instances, this number is specified by its `DesiredCapacity` metric.
If any of it's instances go down, the group will launch a new one to replace it.

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

