package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;

import java.math.BigDecimal;

public class ContratoArmazemHelper {

    private ContratoArmazemHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVoContrato(BigDecimal numContrato) throws Exception {
        try {
            JapeWrapper caDAO = JapeFactory.dao(DynamicEntityNames.CONTRATO_ARMAZENAGEM);
            return caDAO.findByPK(numContrato);
        } catch (Exception e) {
            MGEModelException.throwMe(e);
        }
        return null;
    }
}
