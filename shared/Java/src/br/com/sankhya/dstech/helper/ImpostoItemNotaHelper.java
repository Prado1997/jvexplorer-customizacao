package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;
import java.util.Collection;

public class ImpostoItemNotaHelper {

    private static String INSTANCIA = DynamicEntityNames.IMPOSTO_ITEM_NOTA;

    private ImpostoItemNotaHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVO(BigDecimal nuNota, BigDecimal sequencia, BigDecimal codImp, BigDecimal codInc) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "NUNOTA = ? AND SEQUENCIA = ? AND CODIMP = ? AND CODINC = ?",
                new Object[] {nuNota, sequencia, codImp, codInc}
        );

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Não encontrado impostos para nuNota: " + nuNota + " sequencia: " + sequencia + " codImp: " + codImp + " codInc: " + codInc);
        }
        return (DynamicVO) entities.iterator().next();
    }

    public static Collection<DynamicVO> getVOs(BigDecimal nuNota, BigDecimal sequencia) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "NUNOTA = ? AND SEQUENCIA = ?",
                new Object[] {nuNota, sequencia}
        );

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Não encontrado impostos para nuNota: " + nuNota + " sequencia: " + sequencia);
        }
        return entities;
    }

    public static Collection<DynamicVO> getVOs(BigDecimal nuNota) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "NUNOTA = ?",
                new Object[] {nuNota}
        );

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Não encontrado impostos para nuNota: " + nuNota );
        }
        return entities;
    }
}

