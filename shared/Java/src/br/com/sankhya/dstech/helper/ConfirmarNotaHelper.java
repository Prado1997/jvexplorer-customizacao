package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.PlatformService;
import br.com.sankhya.modelcore.PlatformServiceFactory;
import br.com.sankhya.modelcore.auth.AuthenticationInfo;
import br.com.sankhya.modelcore.comercial.BarramentoRegra;
import br.com.sankhya.modelcore.comercial.CentralFaturamento;
import br.com.sankhya.modelcore.comercial.ConfirmacaoNotaHelper;

import java.math.BigDecimal;

/**
 * Classe auxiliar para confirmar notas fiscais no Sankhya.
 * <p>
 * <b>Atenção:</b> Os métodos desta classe não devem ser utilizados em eventos
 * ou regras de negócio (Barramento, Evento de Fila, etc.) que dependem de
 * contexto de transação da interface. A utilização nesses contextos pode
 * causar bloqueios, erros e comportamento inesperado.
 * <p>
 * Existe a possibilidade de utilizar esta classe em threads ou processos
 * assíncronos, como um Agendador (Job) ou qualquer outra thread
 * controlada externamente.
 *
 * @author Daniel Ratkevicius
 * @since 1.0
 */
public class ConfirmarNotaHelper {

    public static final String CENTRAL_DUPLICATE = "br.com.sankhya.devcenter.central.duplicate";
    public static final String CENTRAL_FATURANDO = "br.com.sankhya.mgecom.centralnotas.NotaFaturamento";
    public static final String CENTRAL_CONFIRMANDO = "CabecalhoNota.confirmando.nota";

    /**
     * Construtor privado para evitar a instanciação da classe.
     */
    private ConfirmarNotaHelper()   {
        throw new UnsupportedOperationException("Não é permitido instanciar esta classe");
    }

    /**
     * Confirma uma nota fiscal utilizando o helper padrão do Sankhya.
     * <p>
     * Este método utiliza o {@link BarramentoRegra} para a confirmação da nota.
     *
     * @param nuNota O número único da nota (NUUNOTA) a ser confirmada.
     * @throws Exception Caso ocorra um erro durante a confirmação da nota.
     */
    public static void confirmarNota(BigDecimal nuNota) throws Exception {
        try {
            BarramentoRegra barramentoConfirmacao = BarramentoRegra.build(CentralFaturamento.class, "regrasConfirmacaoSilenciosa.xml", AuthenticationInfo.getCurrent());
            barramentoConfirmacao.setValidarSilencioso(true);
            ConfirmacaoNotaHelper.confirmarNota(nuNota, barramentoConfirmacao);

        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro ao tentar confirmar a nota: <br>" + e.getMessage(), e);
        }
    }

    /**
     * Confirma uma nota fiscal utilizando o serviço de plataforma do Sankhya.
     * <p>
     * Este método utiliza o serviço de plataforma <code>@core:confirmacao.nota.service</code>
     * para a confirmação da nota.
     *
     * @param nuNota O número único da nota (NUUNOTA) a ser confirmada.
     * @throws Exception Caso ocorra um erro durante a confirmação da nota.
     */
    public static void confirmarNotaService(BigDecimal nuNota) throws Exception {
        try {
            PlatformService confirmarNotaService = PlatformServiceFactory.getInstance().lookupService("@core:confirmacao.nota.service");
            confirmarNotaService.set("nunota", nuNota);
            confirmarNotaService.set("execAndCommit", false);
            confirmarNotaService.execute();
        } catch (Exception e) {
            throw MGEModelException.prettyMsg("Erro ao tentar confirmar a nota: <br>" + e.getMessage(), e);
        }
    }

    /**
     * Retorna se a nota está sendo confirmada.
     */
    public static boolean isConfirmando() {
        Object property = JapeSession.getProperty(CENTRAL_CONFIRMANDO);
        return property instanceof Boolean && (Boolean) property;
    }

    /**
     * Retorna se está em processo de faturamento.
     */
    public static boolean isFaturando() {
        Object propertyFaturando = JapeSession.getProperty(CENTRAL_FATURANDO, false);
        return propertyFaturando instanceof Boolean && (Boolean) propertyFaturando;
    }


    /**
     * Retorna se está duplicando nota.
     */
    public static boolean isDuplicando() {
        Object propertyFaturando = JapeSession.getProperty(CENTRAL_DUPLICATE, false);
        return propertyFaturando instanceof Boolean && (Boolean) propertyFaturando;
    }
}
