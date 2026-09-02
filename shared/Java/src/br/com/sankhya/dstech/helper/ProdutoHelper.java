package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.jape.wrapper.fluid.FluidUpdateVO;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.dwfdata.vo.ProdutoVO;
import br.com.sankhya.modelcore.util.DynamicEntityNames;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;
import java.util.Collection;

/**
 * Classe auxiliar para operações com Produto (TGFPRO).
 * Cobre tanto produtos quanto serviços (USOPROD = 'S').
 * Não pode ser instanciada.
 */
public class ProdutoHelper {

    private static String INSTANCIA = DynamicEntityNames.PRODUTO;

    private ProdutoHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    /**
     * Busca um produto pelo código.
     *
     * @param codProd código do produto (CODPROD)
     * @return DynamicVO do produto
     * @throws MGEModelException se o produto não for encontrado
     */
    public static DynamicVO getVO(BigDecimal codProd) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "CODPROD = ? ", new Object[] {codProd});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro! (ProdutoHelper)<br><br>Não encontrado Produto: " + codProd);
        }
        return (DynamicVO) entities.iterator().next();
    }

    /**
     * Busca um produto do tipo serviço (USOPROD = 'S') pelo código.
     *
     * @param codProd código do produto (CODPROD)
     * @return DynamicVO do serviço
     * @throws MGEModelException se não for encontrado serviço com esse código
     */
    public static DynamicVO getVOServico(BigDecimal codProd) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA,
                "CODPROD = ? AND USOPROD = 'S'", new Object[] {codProd});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro! (ProdutoHelper)<br><br>Não encontrado Serviço: " + codProd);
        }
        return (DynamicVO) entities.iterator().next();
    }

    /**
     * Ativa o produto (ATIVO = 'S'). Valida existência antes de atualizar.
     */
    public static void ativarProduto(BigDecimal codProd) throws Exception {
        atualizarAtivo(codProd, "S");
    }

    /**
     * Desativa o produto (ATIVO = 'N'). Valida existência antes de atualizar.
     */
    public static void desativarProduto(BigDecimal codProd) throws Exception {
        atualizarAtivo(codProd, "N");
    }

    private static void atualizarAtivo(BigDecimal codProd, String ativo) throws Exception {
        try {
            // valida existência - getVO lança MGEModelException se não encontrar
            getVO(codProd);

            JapeWrapper prodDAO = JapeFactory.dao(INSTANCIA);
            FluidUpdateVO fluidUpdateVO = prodDAO.prepareToUpdateByPK(codProd);
            fluidUpdateVO.set("ATIVO", ativo);
            fluidUpdateVO.update();

        } catch (Exception e) {
            String acao = "S".equals(ativo) ? "ativar" : "desativar";
            throw MGEModelException.prettyMsg("Erro ao " + acao + " o produto: " + e.getMessage(), e);
        }
    }

    //assim posso usar os getters nativo
    public static ProdutoVO mapVoDwfData(DynamicVO dynVO) {
        return (ProdutoVO) ((DynamicVO) dynVO).wrapInterface(ProdutoVO.class);
    }
}
