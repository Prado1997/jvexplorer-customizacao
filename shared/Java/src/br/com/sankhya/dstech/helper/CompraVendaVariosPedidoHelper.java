package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.dao.JdbcWrapper;
import br.com.sankhya.jape.sql.NativeSql;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.math.BigDecimal;

public class CompraVendaVariosPedidoHelper {

    private CompraVendaVariosPedidoHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    /**
     * Vincula os itens da nota destino aos itens da nota de origem na TGFVAR,
     * casando por produto (CODPROD) e atendendo a quantidade integral (QTDNEG).
     *
     * @param nunotaOrig nota de origem (ex: pedido)
     * @param nunota     nota destino (ex: nota gerada a partir do pedido)
     * @throws MGEModelException se ocorrer erro na inclusão dos vínculos
     */
    public static void incluirVAR(BigDecimal nunotaOrig, BigDecimal nunota) throws MGEModelException {
        EntityFacade dwfEntityFacade = EntityFacadeFactory.getDWFFacade();
        JdbcWrapper jdbc = dwfEntityFacade.getJdbcWrapper();
        NativeSql nativeSql = null;

        try {
            jdbc.openSession();

            nativeSql = new NativeSql(jdbc);
            nativeSql.appendSql("INSERT INTO TGFVAR (NUNOTA, SEQUENCIA, NUNOTAORIG, SEQUENCIAORIG, QTDATENDIDA)");
            nativeSql.appendSql(" SELECT I.NUNOTA, I.SEQUENCIA, VAR.NUNOTA, VAR.SEQUENCIA, I.QTDNEG");
            nativeSql.appendSql(" FROM TGFITE I");
            nativeSql.appendSql(" INNER JOIN TGFITE VAR ON VAR.CODPROD = I.CODPROD AND VAR.NUNOTA = :NUNOTAORIG");
            nativeSql.appendSql(" WHERE I.NUNOTA = :NUNOTA");
            nativeSql.setNamedParameter("NUNOTAORIG", nunotaOrig);
            nativeSql.setNamedParameter("NUNOTA", nunota);
            nativeSql.executeUpdate();

        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro ao tentar incluir registro na TGFVAR: <br>" + e.getMessage(), e);

        } finally {
            NativeSql.releaseResources(nativeSql);
            JdbcWrapper.closeSession(jdbc);
        }
    }
}
