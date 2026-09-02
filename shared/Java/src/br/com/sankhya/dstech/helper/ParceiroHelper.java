package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;
import java.util.Collection;

public class ParceiroHelper {

    private static String INSTANCIA = DynamicEntityNames.PARCEIRO;

    private ParceiroHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVO(BigDecimal codParc) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "CODPARC = ? ", new Object[] {codParc});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Não encontrado codParc: " + codParc);
        }
        return (DynamicVO) entities.iterator().next();
    }

    public static void atualizaCtaCtb(BigDecimal codParc, BigDecimal codCtaCtb, int nroConta) throws MGEModelException {
        try {
            if(nroConta < 1 || nroConta > 4) throw new MGEModelException("O número da conta deve ser entre 1 e 4.");

            String campoConta = "CODCTACTB";
            if (nroConta > 1) {
                campoConta = campoConta + nroConta;
            }

            JapeWrapper parcDAO = JapeFactory.dao(INSTANCIA);
            parcDAO.prepareToUpdateByPK(codParc)
                    .set(campoConta, codCtaCtb)
                    .update();
        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro ao atualizar ctactb no Parceiro: " + e.getMessage(), e);
        }
    }

}

