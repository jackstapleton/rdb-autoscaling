// asg/util.q

.util.free:{ {1!flip (`state, `$ x[0]) ! "SJJJJJJ"$ .[flip (x[1]; x[2], 3# enlist ""); (0;::); ssr[;":";""]]} (" " vs ' system "free") except\: enlist ""};
.util.getMemUsage:{100 * 1 - (%) . .util.free[][`Mem;`free`total]};

/ aws cli commands should be wrapped in a retry loop as they may timeout when aws is under load
.util.sys.runWithRetry:{[cmd]
    n: 0;
    while[not last res:.util.sys.runSafe cmd; if[10 < n+: 1; 'res 0] ];
    res 0
 };

.util.sys.runSafe: @[{(system x;1b)};;{(x;0b)}];

/ aws ec2 cli commands
.util.aws.getInstanceId: {last " " vs first system "ec2-metadata -i"};

.util.aws.describeInstance:{[instanceId]
    res: .util.sys.runWithRetry "aws ec2 describe-instances --filters  \"Name=instance-id,Values=",instanceId,"\"";
    res: (.j.k "\n" sv res)`Reservations;
    if[() ~ res; 'instanceId," is not an instance"];
    flip first res`Instances
 };

.util.aws.getGroupName:{[instanceId]
    tags: .util.aws.describeInstance[instanceId]`Tags;
    res: first exec Value from raze[tags] where Key like "aws:autoscaling:groupName";
    if[() ~ res; 'instanceId," is not in an autoscaling group"];
    res
 };

/ aws autoscaling cli commands
.util.aws.describeASG:{[groupName]
    res: .util.sys.runWithRetry "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name ",groupName;
    res: flip (.j.k "\n" sv res)`AutoScalingGroups;
    if[() ~ res; 'groupName," is not an autoscaling group"];
    res
 };

.util.aws.getDesiredCapacity:{[groupName]
    first .util.aws.describeASG[groupName]`DesiredCapacity
 };

.util.aws.setDesiredCapacity:{[groupName;n]
    .util.sys.runWithRetry "aws autoscaling set-desired-capacity --auto-scaling-group-name ",groupName," --desired-capacity ",string n
 };

.util.aws.scale:{[groupName]
    .util.aws.setDesiredCapacity[groupName] 1 + .util.aws.getDesiredCapacity groupName;
 };

.util.aws.terminate:{[instanceId]
    .j.k "\n" sv .util.sys.runWithRetry "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"
 };

/ aws cloudwatch put-metric-data
.util.aws.putMetricDataCW:{[namespace;dimensions;metric;unit;data]
    .util.sys.runWithRetry "aws cloudwatch put-metric-data --namespace ",namespace," --dimensions ",dimensions," --metric-name ",metric," --unit ",unit," --value ",data
 };

.util.aws.putUsedMemoryCW:{[instanceId;groupName;memory]
    .util.aws.putMetricDataCW["RdbCluster";"InstanceId=",instanceId,",AutoScalingGroup=",groupName;"UsedMemory";"Bytes";string memory];
 };

.util.aws.putMemoryPercentCW:{[instanceId;groupName;memory]
    .util.aws.putMetricDataCW["RdbCluster";"InstanceId=",instanceId,",AutoScalingGroup=",groupName;"MemoryUsage";"Percent";string memory];
 };

.util.aws.putUpdCountCW:{[instanceId;groupName;i]
    .util.aws.putMetricDataCW["RdbCluster";"AutoScalingGroup=",groupName;"UpdMessages";"Count";string i];
 };

/ logging functions
.util.const.ip: "." sv string `int$ 0x0 vs .z.a;
.util.tmp.hbTime: .z.p;
.util.tmp.subTime: .z.p;
.util.tmp.metricTime: .z.p;
.util.tmp.asgTime: .z.p;

.util.lg: {-1 " | " sv .util.string (.z.p;.util.const.ip;x);};
.util.string: {$[not type x; .z.s each x; 10h = abs type x; x; string x]};

.util.hb:{[]
    if[not .z.p > .util.tmp.hbTime + 00:00:30; :(::)];
    .util.lg "HEARTBEAT";
    .util.tmp.hbTime: .z.p;
 };

.util.putSubMetricsCW:{[]
    if[not .z.p > .util.tmp.metricTime + 00:02; :(::)];
    .sub.monitorMemory[];
    mem: .util.free[]`Mem;
    perc:100 * 1 - (%) . mem`free`total;
    .util.lg "Percentage memory usage of server at - ",string[perc],"%";
    .util.aws.putMemoryPercentCW[.aws.instanceId;.aws.groupName] perc;
    .util.aws.putUsedMemoryCW[.aws.instanceId;.aws.groupName] mem`used;
    if[.sub.live; .util.aws.putUpdCountCW[instanceId;groupName] .sub.i];
    .util.tmp.metricTime: .z.p;
 };

.util.lgSubInfo:{[]
    if[not .z.p > .util.tmp.subTime + 00:05; :(::)];
    .util.lg ".sub.i = ", string .sub.i;
    .util.tmp.subTime: .z.p;
 };

.util.lgAsgInfo:{[]
    if[not .z.p > .util.tmp.asgTime + 00:05; :(::)];
    .util.lg ".u.i = ", string .u.i;
    if[count .u.asg.tab; show .u.asg.tab];
    .util.tmp.asgTime: .z.p;
 };
