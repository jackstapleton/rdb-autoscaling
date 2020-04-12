// asg/util.q

.util.isAws: not .z.h like "desktop*";

.util.free:{ {1!flip (`state, `$ x[0]) ! "SJJJJJJ"$ .[flip (x[1]; x[2], 3# enlist ""); (0;::); ssr[;":";""]]} (" " vs ' system "free") except\: enlist ""};
.util.getMemUsage:{100 * (%) . .util.free[][`Mem;`used`total]};

/ aws cli commands should be wrapped in a retry loop as they may timeout when aws is under load
.util.sys.runWithRetry:{[cmd]
    n: 0;
    while[not last res:.util.sys.runSafe cmd;
        system"sleep 1";
        if[10 < n+: 1; 'res 0];
        ];
    res 0
 };

.util.sys.runSafe: .Q.trp[{(system x;1b)};;{-1 x,"\n",.Q.sbt[y];(x;0b)}];

/ aws ec2 cli commands
.util.aws.getInstanceId:{[]
    if[not .util.isAws; :"testInst"];
    last " " vs first system "ec2-metadata -i"
    };

.util.aws.describeInstance:{[instanceId]
    res: .util.sys.runWithRetry "aws ec2 describe-instances --filters  \"Name=instance-id,Values=",instanceId,"\"";
    res: (.j.k "\n" sv res)`Reservations;
    if[() ~ res; 'instanceId," is not an instance"];
    flip first res`Instances
 };

.util.aws.getGroupName:{[instanceId]
    if[not .util.isAws; :"testAsg"];
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
    if[not .util.isAws; :.util.lg "aws autoscaling set-desired-capacity --auto-scaling-group-name ",groupName," --desired-capacity  1"];
    .util.aws.setDesiredCapacity[groupName] 1 + .util.aws.getDesiredCapacity groupName;
 };

.util.aws.terminate:{[instanceId]
    if[not .util.isAws; :.util.lg "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"];
    .j.k "\n" sv .util.sys.runWithRetry "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"
 };

/ aws cloudwatch put-metric-data
.util.aws.putMetricDataCW:{[namespace;dimensions;metric;unit;data]
    if[not .util.isAws; :.util.lg "aws cloudwatch put-metric-data --namespace ",namespace," --dimensions ",dimensions," --metric-name ",metric," --unit ",unit," --value ",data];
    .util.sys.runWithRetry "aws cloudwatch put-metric-data --namespace ",namespace," --dimensions ",dimensions," --metric-name ",metric," --unit ",unit," --value ",data
 };

/ logging functions
.util.const.ip: "." sv string `int$ 0x0 vs .z.a;
.util.string: {$[not type x; .z.s each x; 10h = abs type x; x; string x]};
.util.lg: {-1 " | " sv .util.string (.z.p;.util.const.ip;x);};

.util.tmp.hbTime: .z.p;
.util.hb:{[]
    if[.z.p > .util.tmp.hbTime + 00:00:30;
            .util.lg "HEARTBEAT";
            .util.tmp.hbTime: .z.p;
            ];
 };
