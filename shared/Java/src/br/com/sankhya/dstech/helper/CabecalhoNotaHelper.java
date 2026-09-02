package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.dwfdata.vo.CabecalhoNotaVO;
import br.com.sankhya.modelcore.util.DynamicEntityNames;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;
import java.util.Collection;

public class CabecalhoNotaHelper {

    private static String INSTANCIA = DynamicEntityNames.CABECALHO_NOTA;

    private CabecalhoNotaHelper()  {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    public static DynamicVO getVo(BigDecimal nuNota) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA, "NUNOTA = ?", nuNota);

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Não encontrado nuNota: " + nuNota);
        }
        return (DynamicVO) entities.iterator().next();
    }

    public static Boolean existeNotaContrato(BigDecimal numContrato) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA, "NUMCONTRATO = ?", numContrato);

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        return !entities.isEmpty();
    }

    //assim posso usar os getters nativo
    public static CabecalhoNotaVO mapVoDwfData(DynamicVO dynVO) {
        return (CabecalhoNotaVO) ((DynamicVO) dynVO).wrapInterface(CabecalhoNotaVO.class);
    }
}
