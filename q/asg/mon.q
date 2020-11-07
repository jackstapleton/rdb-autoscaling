/ send cloudwatch metrics from server

while[null .mon.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];

system "l asg/util.q"


/ ec2 instance id and asg groupname needed to scale asg in and out
.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];


/ launch a new server in the ASG when threshold reached
.mon.scaleThreshold: "I"$ getenv `SCALETHRESHOLD;
.mon.scaled: 0b;

.mon.monitorMemory:{[]
    if[not .mon.scaled;
        .util.lg "Checking memory";

        if[.util.getMemUsage[] > .mon.scaleThreshold;
                .util.lg "Memory has breached .mon.scaleThreshold - ", string .mon.scaleThreshold;

                .util.aws.scale .aws.groupName;
                .mon.scaled: 1b;
                ];
        ];
 };


/ publish to the tickerplant
.mon.sym:` sv (`$getenv`APP),.z.h;
.mon.pub:{ neg[.mon.TP] @ (`.u.upd; `MemUsage; .mon.sym,.util.free[][`Mem;`total`free`used]) };


/ set up timer

.util.name:`mon;

.z.ts:{[]
    .util.hb[];
    .mon.monitorMemory[];
    .mon.pub[];
 };

system "t 500"
