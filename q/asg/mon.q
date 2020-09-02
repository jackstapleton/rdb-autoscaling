/ send cloudwatch metrics from server

system "l asg/util.q"


/ ec2 instance id and asg groupname needed to scale asg in and out
.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];


/ launch a new server in the ASG when threshold reached
.mon.scaleThreshold: "I"$ getenv `SCALETHRESHOLD;
.mon.scaled: 0b;

.mon.monitorMemory:{[]
    if[not .mon.scaled;
        if[.util.getMemUsage[] > .mon.scaleThreshold;
                .util.aws.scale .aws.groupName;
                .mon.scaled: 1b;
                ];
        :(::);
        ];
 };


/ publish cloudwatch metrics
.mon.runTime: .z.p;
.mon.namespace: "RdbCluster";
.mon.dimensions: "InstanceId=",.aws.instanceId,",AutoScalingGroup=",.aws.groupName;
.mon.metricNames: "Memory",/:("Percent";"Total";"Used";"Free";"Shared";"BuffCache";"Available");
.mon.metricUnits: enlist["Percent"], 6#enlist "Bytes";

.mon.publishMetrics:{[]
    if[.z.p > .mon.runTime + 00:01:00;
            mem: .util.free[]`Mem;
            perc: 100 * (%) . mem`used`total;
            vals: string perc, value mem;
            .util.aws.putMetricDataCW[.mon.namespace;.mon.dimensions] .' flip (.mon.metricNames;.mon.metricUnits;vals);
            `.mon.runTime set .z.p;
            ];
 };


/ set up timer
.z.ts:{[]
    .mon.monitorMemory[];
    .mon.publishMetrics[];
 };

system "t 500"
