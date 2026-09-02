package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;

import java.math.BigDecimal;

public class EmpresaHelper {

    private EmpresaHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVoEmpresa(BigDecimal codEmp) throws Exception {
        try {
            JapeWrapper empDAO = JapeFactory.dao(DynamicEntityNames.EMPRESA);
            return empDAO.findByPK(codEmp);
        } catch (Exception e) {
            MGEModelException.throwMe(e);
        }
        return null;
    }
}
