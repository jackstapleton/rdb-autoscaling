/q asg/r-asg.q [host]:port[:usr:pwd] [host]:port[:usr:pwd]

system "l asg/sub.q"

.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

/ open connection to tickerplant and gateway
while[null .sub.TP: @[{hopen `$":", .u.x: x 0}; .z.x; 0Ni];
        -1 string[.z.p]," retrying tickerplant - ",.u.x;
        system "sleep 1" ];

.sub.GW: @[{hopen `$":", .u.gw: x 1}; .z.x; 0Ni];

/ thresholds for percentage memory usage of the server
.sub.scaleThreshold: 60;     / launch a new server in the ASG when threshold reached
.sub.rollThreshold: 80;      / tell tickerplant to move on to the next subscriber

.sub.live: 0b;      / process is the live subscriber
.sub.scaled: 0b;    / process has launched the next server
.sub.rolled: 0b;    / process has cut its subscription

/ upd counter, must keep track of upd msgs received as tickerplant
/ will use it to tell the next rdb where to start replaying from
.sub.i: 0;

/ monitor memory every 5 seconds
.util.hbTime: .z.p;
.z.ts: {.sub.monitorMemory[]; .util.hb[];};
system"t 5000"

/ clear data at end of day
.u.end: {[dt] .sub.clear dt+1};


/ register with gateway so process can be queried
if[not null .sub.GW;
        neg[.sub.GW] @ (`.gw.register;.z.h) ];

/ tickerplant saves subscriptions
/ so all tab and sym subscriptions must be sent at once
/ .u.asg.sub[tabList;symLists;shardName]
/ e.g. neg[.sub.TP] (`.u.asg.sub;`;`;`shard1)
/ e.g. neg[.sub.TP] (`.u.asg.sub;`Trade;`;`shard2)
/ e.g. neg[.sub.TP] (`.u.asg.sub;`Quote;enlist `aa`bb`cc;`shard3)
/ e.g. neg[.sub.TP] (`.u.asg.sub;`Quote`Trade;(`;`GM`MSFT`APPL`JPM);`shard4)

neg[.sub.TP] @ (`.u.asg.sub; `; `; `$ .aws.groupName, ".r-asg");
