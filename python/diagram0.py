from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2

Cluster._default_graph_attrs['labeljust'] = 'r'


def build(title, n):

    if n in [0, 5]:
        orientation = "LR"
    else:
        orientation = "TB"


    with Diagram(title, direction=orientation, curvestyle="curved"):
        with Cluster("AWS"):
            tp = EC2("tickerplant")
            gw = EC2("gateway")
            with Cluster("RDB Autoscaling group"):
                rdbs = []
                if n == 0:
                    rdbs.append(EC2(f"rdb-1"))
                elif n == 5:
                    rdbs.append(EC2(f"rdb-5"))
                else:
                    for i in range(n+1):
                        if i == n:
                            with Cluster("Live RDB"):
                                rdbs.append(EC2(f"rdb-{i+1}"))
                        else:
                            with Cluster("Rolled RDBs"):
                                rdbs.append(EC2(f"rdb-{i+1}"))

            tp >> Edge(color="darkgreen") >> rdbs[-1:]
            rdbs >> Edge(color="firebrick") << gw


if __name__ == '__main__':
    # TITLES = ["Stack Launch",
    #           "Scaling Out - 1",
    #           "Scaling Out - 2",
    #           "Scaling Out - 3",
    #           "Fully Scaled",
    #           "End of Day Scale in"]
    # for rdb_num, title in enumerate(TITLES):
    #     build(title, rdb_num)
    build("Stack Launch", 0)




