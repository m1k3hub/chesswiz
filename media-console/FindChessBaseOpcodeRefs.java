// @category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Function;
import ghidra.program.model.scalar.Scalar;
import java.util.HashSet;
import java.util.Set;

public class FindChessBaseOpcodeRefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        Set<String> seen = new HashSet<>();
        int[] opcodes = {2, 3, 4, 6, 8, 14};
        for (Instruction instruction : currentProgram.getListing().getInstructions(true)) {
            for (int i = 0; i < instruction.getNumOperands(); i++) {
                Object[] objects = instruction.getOpObjects(i);
                for (Object object : objects) {
                    if (!(object instanceof Scalar)) continue;
                    long value = ((Scalar) object).getUnsignedValue();
                    for (int opcode : opcodes) {
                        if (value != opcode && value != (opcode | 0x1000000L)) continue;
                        Function function = getFunctionContaining(instruction.getAddress());
                        if (function == null) continue;
                        String key = function.getEntryPoint().toString() + ":" + opcode;
                        if (seen.add(key)) println("OPCODE " + opcode + " "
                                + function.getEntryPoint() + " " + function.getName()
                                + " at " + instruction.getAddress());
                    }
                }
            }
        }
    }
}
