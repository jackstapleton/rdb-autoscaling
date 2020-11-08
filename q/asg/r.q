/q asg/r.q [host]:port[:usr:pwd]

system "l asg/util.q"
system "l asg/sub.q"

/ open connection to tickerplant and logstreamer
while[null .sub.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni] ];
while[null .sub.LS: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 1; 0Ni] ];

/ ec2 instance id and asg groupname needed to scale asg in and out
.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

/ thresholds for percentage memory usage of the server
.sub.rollThreshold: "I"$ getenv `ROLLTHRESHOLD;       / tell tickerplant to move on to the next subscriber

.sub.live: 0b;      / process is the live subscriber
.sub.scaled: 0b;    / process has launched the next server

/ upd counter, must keep track of upd msgs received as tickerplant
/ will use it to tell the next rdb where to start replaying from
.sub.i: 0;

/ clear data at end of day
.u.end: .sub.end;

/ tickerplant kicks off log replay
/ so duplicate .u.asg.sub calls cannot be made at
/ e.g., neg[.sub.TP] (`.u.asg.sub;`Quote`Trade;(`;`GM`MSFT`APPL`JPM);`shard4)
neg[.sub.TP] @ (`.u.asg.sub; `MemUsage`Quote`Trade; ```; `$ .aws.groupName, ".r-asg");

.util.name:`$"rdb-asg";
.util.tmp.subTime: .z.p;
.z.ts:{[]
    .util.hb[];
    if[.z.p > .util.tmp.subTime + 00:01;
            .sub.monitorMemory[];
            .util.lg "Percentage memory usage of server at - ",string[.util.getMemUsage[]],"%";
            .util.lg ".sub.i = ", string .sub.i;
            if[.sub.live;
                .util.aws.putMetricDataCW["RdbCluster";"AutoScalingGroups=",.aws.groupName;"UpdCount";"Count";string .sub.i]];
            .util.tmp.subTime: .z.p;
            ];
 };
system "t 200";
