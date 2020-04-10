/ send cloudwatch metrics from server

system "l asg/util.q"

.aws.instanceId: .util.aws.getInstanceId[];
.aws.groupName: .util.aws.getGroupName[.aws.instanceId];

runTime: .z.p;
namespace: "RdbCluster";
dimensions: "InstanceId=",.aws.instanceId,",AutoScalingGroup=",.aws.groupName;
metricNames: "Memory",/:("Percent";"Total";"Used";"Free";"Shared";"BuffCache";"Available");
metricUnits: enlist["Percent"], 6#enlist "Bytes";

.z.ts:{[]
    .util.hb[];
    if[.z.p > runTime + 00:02:30;
            .util.lg "Sending Cloudwatch Metrics";
            show mem: .util.free[]`Mem;
            perc: 100 * (%) . mem`used`total;
            vals: string perc, value mem;
            .util.aws.putMetricDataCW[namespace;dimensions] .' flip (metricNames;metricUnits;vals);
            `runTime set .z.p;
            ];
 };

system "t 500"
