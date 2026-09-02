package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;

import java.math.BigDecimal;

public class TipoOperacaoHelper {

    private TipoOperacaoHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVoTipoOperacao(BigDecimal codTipOper) throws Exception {
        try {
            JapeWrapper caDAO = JapeFactory.dao(DynamicEntityNames.TIPO_OPERACAO);

            return caDAO.findOne("CODTIPOPER = ? AND DHALTER = (SELECT MAX(DHALTER) FROM TGFTOP TOP WHERE TOP.CODTIPOPER = ?)" , new Object[] { codTipOper, codTipOper });
        } catch (Exception e) {
            MGEModelException.throwMe(e);
        }
        return null;
    }
}
