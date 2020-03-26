/q asg/r-asg.q [host]:port[:usr:pwd] [host]:port[:usr:pwd]

system "l asg/sub.q"


.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

/ set .sub Globals

/ open connection to tickerplant and gateway
.sub.TP: @[{hopen `$":", .u.x: x 0}; .z.x; 0Ni];
.sub.GW: @[{hopen `$":", .u.gw: x 1}; .z.x; 0Ni];

.sub.doReplay: 1b;       / whether to replay logs
.sub.live: 0b;           / whether process is the live subscriber
.sub.scaled: 0b;         / whether process has launched the next server
.sub.rolled: 0b;         / whether process has cut its subscription

.sub.scaleThreshold: 90;     / when to launch the next server - percentage memory usage
.sub.rollThreshold: 95;      / when to stop subscribing - percentage memory usage


/ upd counter, must keep track as tickerplant will use
/ it to tell the next rdb where to start replaying from
.sub.i: 0;


/ monitor memory every 5 seconds
.z.ts: {-1 "HEARTBEAT"; .sub.monitorMemory[]};

system"t 5000"

/ clear data at end of day
.u.end: {[dt] .sub.clear dt+1};

/ tickerplant saves subscriptions
/ so all tab and sym subscriptions must be sent at once
/ .u.asg.addSubscriber[tabList;symLists;shardName]

neg[.sub.TP] @ (`.u.asg.addSubscriber; `Trade`Quote; (`;`GM`MSFT`APPL`JPM); `$ .aws.groupName, ".r-asg");

neg[.sub.GW] @ (`.gw.register;.z.h);
