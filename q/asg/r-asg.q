/q asg/r-asg.q [host]:port[:usr:pwd] [host]:port[:usr:pwd]

system "l asg/sub.q"

.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

/ open connection to tickerplant and gateway
while[null .sub.TP: @[{hopen `$":", .u.x: x 0}; .z.x; 0Ni];
        -1 string[.z.p]," retrying tickerplant - ",.u.x;
        system "sleep 1" ];

.sub.GW: @[{hopen `$":", .u.gw: x 1}; .z.x; 0Ni];

/ set globals which coordinate scaling

.sub.scaleThreshold: 90;     / when to launch the next server - percentage memory usage
.sub.rollThreshold: 95;      / when to stop subscribing - percentage memory usage

.sub.live: 0b;      / whether the process is the live subscriber
.sub.scaled: 0b;    / whether the process has launched the next server
.sub.rolled: 0b;    / whether the process has cut its subscription

/ upd counter, must keep track of upd msgs as tickerplant will use
/ it to tell the next rdb where to start replaying from
.sub.i: 0;

/ monitor memory every 5 seconds
.util.hbTime: .z.p;
.z.ts: {.sub.monitorMemory[]; .util.hb[];};
system"t 5000"

/ clear data at end of day
.u.end: {[dt] .sub.clear dt+1};

/ tickerplant saves subscriptions
/ so all tab and sym subscriptions must be sent at once
/ .u.asg.addSubscriber[tabList;symLists;shardName]
neg[.sub.TP] @ (`.u.asg.addSubscriber; `Trade`Quote; (`;`GM`MSFT`APPL`JPM); `$ .aws.groupName, ".r-asg");

/ register with gateway so process can be queried
if[not null .sub.GW;
        neg[.sub.GW] @ (`.gw.register;.z.h) ];
