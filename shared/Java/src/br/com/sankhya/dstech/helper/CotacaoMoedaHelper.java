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

public class CotacaoMoedaHelper {

    private CotacaoMoedaHelper()  {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVo(BigDecimal nuNota) throws Exception {
        try {
            JapeWrapper cabDAO = JapeFactory.dao(DynamicEntityNames.COTACAO_MOEDA);
            return cabDAO.findByPK(nuNota);
        } catch (Exception e) {
            MGEModelException.throwMe(e);
        }
        return null;
    }

    public static Boolean temCotacao(BigDecimal codMoeda) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(DynamicEntityNames.COTACAO_MOEDA, "CODMOEDA = ?", codMoeda);

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        return !entities.isEmpty();
    }

}
