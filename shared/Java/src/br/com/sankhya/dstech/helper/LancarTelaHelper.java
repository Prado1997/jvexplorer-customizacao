package br.com.sankhya.dstech.helper;

import java.math.BigDecimal;
import java.util.Base64;

/**
 * Classe auxiliar para gerar links que abrem telas específicas com filtros.
 * <p>
 * Autor: Jerônimo - DCTM
 */
public class LancarTelaHelper {
    private LancarTelaHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    /**
     * Gera um link para abrir a tela especificada com o filtro fornecido.
     *
     * @param nu   BigDecimal - o número único
     * @param tela Telas - a tela a ser aberta
     * @return String - um link HTML para abrir a tela
     * @utilização LancarTelaHelper.lancarTela(orcamento, LancarTelaHelper.Telas.CENTRAL)
     */
    public static String lancarTela(BigDecimal nu, Telas tela) {
        String base = "/mge/system.jsp#app/";
        String enderecoTela = tela.getTela();
        String filtroTela = "{\"NUNOTA\":\"" + nu + "\"}";

        // ENCODA PARA BASE64
        String enderecoTela64 = Base64.getEncoder().encodeToString(enderecoTela.getBytes());
        String filtroTela64 = Base64.getEncoder().encodeToString(filtroTela.getBytes());

        // CONCATENA STRINGS
        String link = base + enderecoTela64 + "/" + filtroTela64;

        // RESULTADO
        return "<a href=\"" + link + "\" target=\"_top\" title=\"Abrir\" >Abrir na Central!</a>";
    }

    /**
     * Gera um link para abrir a tela especificada com o filtro fornecido, caso nu diferente ZERO.
     *
     * @param tela Telas - a tela a ser aberta
     * @param nu   BigDecimal - o número único
     * @param msgLink String - mensagem que vai aparecer no link da tela
     * @return String - um link HTML para abrir a tela
     * @utilização LancarTelaHelper.lancarTelaCustom(LancarTelaHelper.Telas.CENTRAL, orcamento, msgLink)
     */
    public static String lancarTelaCustom(Telas tela, BigDecimal nu, String msgLink) {

        if(nu == null) return "";
        if(nu.equals(BigDecimal.ZERO)) return "";

        String base = "/mge/system.jsp#app/";
        String enderecoTela = tela.getTela();
        String filtroTela = "{\"NUNOTA\":\"" + nu + "\"}";

        // ENCODA PARA BASE64
        String enderecoTela64 = Base64.getEncoder().encodeToString(enderecoTela.getBytes());
        String filtroTela64 = Base64.getEncoder().encodeToString(filtroTela.getBytes());

        // CONCATENA STRINGS
        String link = base + enderecoTela64 + "/" + filtroTela64;

        // RESULTADO
        return "<br><a href=\"" + link + "\" target=\"_top\" title=\"Abrir\" >"+msgLink+"</a>";
    }

    // Enum para definir as telas e seus valores fixos
    public enum Telas {
        CENTRAL("br.com.sankhya.com.mov.CentralNotas"),
        FINANCEIRO("br.com.sankhya.fin.cad.movimentacaoFinanceira"),
        PORTALCOMPRAS("br.com.sankhya.mgecom.mov.PortalCompras"),
        PORTALVENDAS("br.com.sankhya.mgecom.mov.selecaodedocumento");

        private final String tela;

        Telas(String tela) {
            this.tela = tela;
        }

        public String getTela() {
            return tela;
        }
    }
}
