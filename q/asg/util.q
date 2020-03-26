/ asg/util.q

.util.free:{ {1!flip (`state, `$ x[0]) ! "SJJJJJJ"$ .[flip (x[1]; x[2], 3# enlist ""); (0;::); ssr[;":";""]]} (" " vs ' .util.sys.runWithRetry "free") except\: enlist ""};
.util.getMemUsage:{100 * 1 - (%) . .util.free[][`Mem;`free`total]};

/ aws cli commands should be wrapped in a retry loop as they may timeout when aws is under load
.util.sys.runWithRetry:{[cmd]
    n: 0;
    while[not last res:.util.sys.run cmd; if[10 < n+: 1; 'res 0] ];
    res 0
 };

.util.sys.run: @[{(system x;1b)};;{(x;0b)}];

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
    needed: 1 + .util.aws.getDesiredCapacity groupName;
    .util.aws.setDesiredCapacity[groupName;needed];
    while[not needed = .util.aws.getDesiredCapacity groupName; .util.aws.setDesiredCapacity[groupName;needed] ];
 };

.util.aws.terminate:{[instanceId]
    .j.k "\n" sv .util.sys.runWithRetry "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id ",instanceId," --should-decrement-desired-capacity"
 };
