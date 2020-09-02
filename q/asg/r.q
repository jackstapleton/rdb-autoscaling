/q asg/r.q [host]:port[:usr:pwd]

system "l asg/util.q"
system "l asg/sub.q"

/ open connection to tickerplant
while[null .sub.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];

/ open connection to monitor
while[null .sub.MON: @[{hopen (`::5016; 5000)}; (::); 0Ni]];

/ ec2 instance id and asg groupname needed to scale asg in and out
.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

/ memory threshold to unsub from the tickerplant
.sub.rollThreshold: "I"$ getenv `ROLLTHRESHOLD;

.sub.live: 0b;      / process is the live subscriber

/ upd counter, must keep track of upd msgs received as tickerplant
/ will use it to tell the next rdb where to start replaying from
.sub.i: 0;

/ clear data at end of day
.u.end: .sub.end;

/ tickerplant kicks off log replay
/ so duplicate .u.asg.sub calls cannot be made at
/ e.g., neg[.sub.TP] (`.u.asg.sub;`Quote`Trade;(`;`GM`MSFT`APPL`JPM);`shard4)
neg[.sub.TP] @ (`.u.asg.sub; `; `; `$ .aws.groupName, ".r-asg");
