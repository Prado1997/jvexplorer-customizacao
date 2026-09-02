package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;
import java.util.Collection;

public class ItemComposicaoProdutoHelper {

    private static String INSTANCIA = DynamicEntityNames.ITEM_COMPOSICAO_PRODUTO;

    private ItemComposicaoProdutoHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    /**
     * Busca um único Item de Composicao de Produto (TGFICP) pelo CODEMP.
     * Este método original não é ideal para a validação do kit, mas foi mantido
     * para ilustrar a sua estrutura.
     */
    public static DynamicVO getVO  (
            BigDecimal codProd,
            BigDecimal variacao,
            BigDecimal codLocal,
            String controle,
            BigDecimal codEtapa,
            BigDecimal codMatPrima,
            BigDecimal codLocalMP,
            String controleMP
            ) throws Exception, MGEModelException {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "CODPROD = ? " +
                        "VARIACAO = ? " +
                        "CODLOCAL = ? " +
                        "CONTROLE = ? " +
                        "CODETAPA = ? " +
                        "CODMATPRIMA = ? " +
                        "CODLOCALMP = ? " +
                        "CONTROLEMP = ? "
                , new Object[] {codProd, variacao, codLocal, controle, codEtapa, codMatPrima,codLocalMP, controleMP});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Não encontrado o componente com base nos dados fornecidos!");
        }
        return (DynamicVO) entities.iterator().next();
    }


    /**
     * Retorna todos os itens de composição de um produto (kit) e sua variação.
     * Este é o método que usaremos para a validação.
     */
    public static Collection<DynamicVO> getItensDoKit(BigDecimal codProd) throws Exception, MGEModelException {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "CODPROD = ?", new Object[] {codProd});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        return entities;
    }

}