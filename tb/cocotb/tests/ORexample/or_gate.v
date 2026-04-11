module or_gate(input wire a, 
        input wire b, 
        output wire y
);
assign y = a|b ;

initial begin
    $dumpfile("waves.vcd");
    $dumpvars;
end
endmodule   
