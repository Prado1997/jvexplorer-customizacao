package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.dwfdata.vo.ItemNotaVO;
import br.com.sankhya.modelcore.util.DynamicEntityNames;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;
import java.util.Collection;

/**
 * Classe auxiliar (Helper) para operações relacionadas a itens de nota (ITENS DA TGFCAB).
 * <p>
 * Fornece métodos estáticos para buscar e manipular informações de itens de nota no sistema.
 * Esta classe não pode ser instanciada.
 */
public class ItemNotaHelper {

    private static String INSTANCIA = DynamicEntityNames.ITEM_NOTA;

    /**
     * Construtor privado para impedir a instanciação desta classe utilitária.
     * Tentar instanciar esta classe resultará em uma {@code UnsupportedOperationException}.
     */
    private ItemNotaHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar ItemNotaHelper");
    }

    /**
     * Retorna um {@code DynamicVO} de um item de nota específico usando o número da nota e a sequência.
     * <p>
     * Este método realiza uma busca por chave primária composta na entidade ITEM_NOTA,
     * utilizando o Número Único da Nota (NUNOTA) e a Sequência do item (SEQUENCIA).
     *
     * @param nuNota    Número Único da Nota (NUNOTA) do item a ser encontrado.
     * @param sequencia Número de sequência do item dentro da nota (SEQUENCIA) para a busca.
     * @return O {@code DynamicVO} do item da nota correspondente.
     * @throws MGEModelException Se nenhum item for encontrado para a combinação de {@code nuNota}
     * e {@code sequencia}, ou se ocorrer um erro durante a consulta.
     */
    static public DynamicVO getVo(BigDecimal nuNota, BigDecimal sequencia) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA, "NUNOTA = ? AND SEQUENCIA = ?",
                new Object[]{nuNota, sequencia});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Nota " + nuNota + " sem item na sequencia " + sequencia);
        }
        return (DynamicVO) entities.iterator().next();
    }

    /**
     * Retorna uma coleção de {@code DynamicVO}s contendo todos os itens para um número de nota específico.
     * <p>
     * Este método realiza uma busca por todos os itens associados a um determinado Número Único da Nota (NUNOTA).
     *
     * @param nuNota O Número Único da Nota (NUNOTA) para o qual se deseja buscar os itens.
     * @return Uma {@code Collection} de {@code DynamicVO}s representando os itens da nota.
     * Retorna uma coleção não vazia se itens forem encontrados.
     * @throws MGEModelException Se nenhum item for encontrado para o {@code nuNota} ou se ocorrer
     * um erro durante a consulta.
     */
    static public Collection<DynamicVO> getVos(BigDecimal nuNota) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA, "NUNOTA = ?", nuNota);

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Nota sem itens - nuNota: " + nuNota);
        }
        return entities;
    }

    /**
     * Retorna uma coleção de {@code DynamicVO}s contendo os itens de uma nota filtrados por produto.
     * <p>
     * Este método busca os itens associados a um Número Único da Nota (NUNOTA)
     * que correspondam ao produto informado (CODPROD).
     *
     * @param nuNota  O Número Único da Nota (NUNOTA) para o qual se deseja buscar os itens.
     * @param codProd O código do produto (CODPROD) para filtrar os itens da nota.
     * @return Uma {@code Collection} de {@code DynamicVO}s representando os itens da nota.
     * Retorna uma coleção não vazia se itens forem encontrados.
     * @throws MGEModelException Se nenhum item for encontrado para a combinação de {@code nuNota}
     * e {@code codProd}, ou se ocorrer um erro durante a consulta.
     */
    static public Collection<DynamicVO> getVos(BigDecimal nuNota, BigDecimal codProd) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(INSTANCIA, "NUNOTA = ? AND CODPROD = ?",
                new Object[]{nuNota, codProd});

        @SuppressWarnings("unchecked")
        Collection<DynamicVO> entities = (Collection<DynamicVO>) dwfFacade.findByDynamicFinderAsVO(wrapper);

        if (entities.isEmpty()) {
            throw new MGEModelException("Erro!<br>Nota sem itens - nuNota: " + nuNota + " codProd: " + codProd);
        }
        return entities;
    }

    //assim posso usar os getters nativo
    public static ItemNotaVO mapVoDwfData(DynamicVO dynVO) {
        return (ItemNotaVO) ((DynamicVO) dynVO).wrapInterface(ItemNotaVO.class);
    }
}