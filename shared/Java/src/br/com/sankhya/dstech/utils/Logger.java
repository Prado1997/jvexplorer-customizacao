// Encoding: ISO-8859-1
package br.com.sankhya.dstech.utils;

import br.com.sankhya.jape.dao.JdbcWrapper;
import br.com.sankhya.jape.sql.NativeSql;
import br.com.sankhya.modelcore.auth.AuthenticationInfo;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;
import br.com.sankhya.modelcore.util.MGECoreParameter;

import java.io.PrintWriter;
import java.sql.Timestamp;
import java.io.StringWriter;
import java.math.BigDecimal;

public class Logger {

    private static final String PARAM_LOG_ATIVO = "LOGDEBUGATV";
    private static final String NIVEL_INFO = "INFO";
    private static final String NIVEL_ERROR = "ERROR";

    private Logger() {
        throw new IllegalStateException("Utility class");
    }

    public static void info(String mensagem) {
        gravar(NIVEL_INFO, mensagem, null);
    }

    public static void error(String mensagem, Throwable excecao) {
        gravar(NIVEL_ERROR, mensagem, excecao);
    }

    private static void gravar(String nivel, String mensagem, Throwable excecao) {
        // CAPTURAR ORIGEM AQUI - antes de qualquer chamada de metodo
        // pilha[0] = getStackTrace (JVM)
        // pilha[1] = gravar (Logger privado)
        // pilha[2] = info() ou error() (Logger publico)
        // pilha[3] = CHAMADOR REAL
        String origem = obterOrigem(Thread.currentThread().getStackTrace());
        JdbcWrapper jdbc = null;
        NativeSql sql = null;
        try {
            if ("N".equals(MGECoreParameter.getParameterAsString(PARAM_LOG_ATIVO))) {
                return;
            }
            String stacktrace = excecao != null ? formatarStacktrace(excecao) : null;
            BigDecimal codUsu = obterCodUsuAtual();
            jdbc = EntityFacadeFactory.getDWFFacade().getJdbcWrapper();
            jdbc.openSession();
            sql = new NativeSql(jdbc);
            sql.appendSql("INSERT INTO AD_LOG (IDLOG, DTHLOG, NIVEL, ORIGEM, MENSAGEM, STACKTRACE, CODUSU)");
            sql.appendSql(" VALUES ((SELECT COALESCE(MAX(IDLOG), 0) + 1 FROM AD_LOG), ?, ?, ?, ?, ?, ?)");
            sql.addParameter(new Timestamp(System.currentTimeMillis()));
            sql.addParameter(nivel);
            sql.addParameter(origem);
            sql.addParameter(mensagem);
            sql.addParameter(stacktrace);
            sql.addParameter(codUsu);
            sql.executeUpdate();
        } catch (Exception e) {
            // supressao silenciosa - logger nunca propaga excecao (LOG-07)
        } finally {
            NativeSql.releaseResources(sql);
            JdbcWrapper.closeSession(jdbc);
        }
    }

    private static String obterOrigem(StackTraceElement[] pilha) {
        if (pilha != null && pilha.length > 3) {
            StackTraceElement chamador = pilha[3];
            String nomeCompleto = chamador.getClassName();
            String nomeSimples = nomeCompleto.substring(nomeCompleto.lastIndexOf('.') + 1);
            return nomeSimples + "." + chamador.getLineNumber();
        }
        return "desconhecido";
    }

    private static String formatarStacktrace(Throwable excecao) {
        StringWriter sw = new StringWriter();
        excecao.printStackTrace(new PrintWriter(sw));
        return sw.toString();
    }

    private static BigDecimal obterCodUsuAtual() {
        AuthenticationInfo auth = AuthenticationInfo.getCurrent();
        if (auth == null) {
            return BigDecimal.ZERO;
        }
        BigDecimal codUsu = auth.getUserID();
        return codUsu != null ? codUsu : BigDecimal.ZERO;
    }
}
