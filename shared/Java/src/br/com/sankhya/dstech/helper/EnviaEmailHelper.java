package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.fluid.FluidCreateVO;
import br.com.sankhya.modelcore.util.DynamicEntityNames;

import java.math.BigDecimal;
import java.sql.Timestamp;

/**
 * Classe auxiliar para envio de e-mails via fila de mensagens do Sankhya (FILA_MSG).
 * O envio efetivo é feito pelo serviço de fila do próprio Sankhya.
 * Não pode ser instanciada.
 */
public class EnviaEmailHelper {

    private EnviaEmailHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    /**
     * Insere e-mail na fila de envio usando o SMTP padrão do sistema.
     *
     * @param mensagem      corpo do e-mail (HTML)
     * @param maxtentenvio  máximo de tentativas de envio
     * @param assunto       assunto do e-mail
     * @param email         destinatário
     * @param codusu        usuário associado ao envio
     */
    public static void insereEmail(char[] mensagem, BigDecimal maxtentenvio, String assunto,
            String email, BigDecimal codusu) throws Exception {
        inserirNaFila(mensagem, maxtentenvio, assunto, email, codusu, null);
    }

    /**
     * Insere e-mail na fila de envio usando uma conta SMTP específica.
     *
     * @param mensagem      corpo do e-mail (HTML)
     * @param maxtentenvio  máximo de tentativas de envio
     * @param assunto       assunto do e-mail
     * @param email         destinatário
     * @param codusu        usuário associado ao envio
     * @param codSMTP       código da conta SMTP (TSISMT) a utilizar
     */
    public static void insereEmail(char[] mensagem, BigDecimal maxtentenvio, String assunto,
            String email, BigDecimal codusu, BigDecimal codSMTP) throws Exception {
        inserirNaFila(mensagem, maxtentenvio, assunto, email, codusu, codSMTP);
    }

    private static void inserirNaFila(char[] mensagem, BigDecimal maxtentenvio, String assunto,
            String email, BigDecimal codusu, BigDecimal codSMTP) throws Exception {
        FluidCreateVO mensagemVO = JapeFactory.dao(DynamicEntityNames.FILA_MSG).create();
        mensagemVO.set("DTENTRADA", new Timestamp(System.currentTimeMillis()));
        mensagemVO.set("MENSAGEM", mensagem);
        mensagemVO.set("TIPOENVIO", "E");
        mensagemVO.set("MAXTENTENVIO", maxtentenvio);
        mensagemVO.set("ASSUNTO", assunto);
        mensagemVO.set("EMAIL", email);
        mensagemVO.set("MIMETYPE", "text/html");
        mensagemVO.set("CODUSU", codusu);
        mensagemVO.set("STATUS", "Pendente");
        mensagemVO.set("CODCON", BigDecimal.ZERO);
        mensagemVO.set("TENTENVIO", BigDecimal.ZERO);
        mensagemVO.set("REENVIAR", "N");
        if (codSMTP != null) {
            mensagemVO.set("CODSMTP", codSMTP);
        }
        mensagemVO.save();
    }
}
