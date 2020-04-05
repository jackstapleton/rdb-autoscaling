
/ (`.u.stream; `:tplog/sym2020.01.01; 100; 200)
.u.stream:{[tplog;start;end]
    .u.start: start;
    -11!(tplog;end);
    delete start from `.u;
 };

upd: {if[.u.start < .u.i+:1; neg[.z.w] @ (`upd;x;y); neg[.z.w][]]};
