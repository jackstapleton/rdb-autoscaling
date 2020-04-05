/q asg/r.q [host]:port[:usr:pwd]

system "l asg/util.q"
system "l asg/sub.q"

/ open connection to tickerplant and gateway
while[null .sub.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni];

.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

/ thresholds for percentage memory usage of the server
.sub.scaleThreshold: 60;     / launch a new server in the ASG when threshold reached
.sub.rollThreshold: 80;      / tell tickerplant to move on to the next subscriber

.sub.live: 0b;      / process is the live subscriber
.sub.scaled: 0b;    / process has launched the next server
.sub.rolled: 0b;    / process has cut its subscription

/ upd counter, must keep track of upd msgs received as tickerplant
/ will use it to tell the next rdb where to start replaying from
.sub.i: 0;

/ clear data at end of day
.u.end: {[dt] .sub.clear dt+1};

/ tickerplant saves subscriptions
/ so all tab and sym subscriptions must be sent at once
/ .u.asg.sub[tabList;symLists;shardName]
/ e.g. neg[.sub.TP] (`.u.asg.sub;`;`;`shard1)
/ e.g. neg[.sub.TP] (`.u.asg.sub;`Trade;`;`shard2)
/ e.g. neg[.sub.TP] (`.u.asg.sub;`Quote;`GM`MSFT`APPL`JPM;`shard3)
/ e.g. neg[.sub.TP] (`.u.asg.sub;`Quote`Trade;(`;`GM`MSFT`APPL`JPM);`shard4)

neg[.sub.TP] @ (`.u.asg.sub; `; `; `$ .aws.groupName, ".r-asg");
