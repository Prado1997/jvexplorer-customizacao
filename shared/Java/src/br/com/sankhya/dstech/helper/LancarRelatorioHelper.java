package br.com.sankhya.dstech.helper;

import br.com.sankhya.ws.ServiceContext;
import com.sankhya.util.SessionFile;
import com.sankhya.util.UIDGenerator;
import org.apache.commons.io.FileUtils;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;

/**
 * Classe utilitária para lançar relatórios em sessão temporária e gerar links de visualização.
 * <p>
 * Esta classe é responsável por:
 * <ul>
 *     <li>Detectar o MIME type de arquivos;</li>
 *     <li>Criar arquivos de sessão via {@link SessionFile};</li>
 *     <li>Gerar links HTML para visualização dos arquivos;</li>
 *     <li>Fornecer fallback de detecção de MIME via enum {@link MimeType}.</li>
 * </ul>
 *
 * <p>Uso típico:</p>
 * <pre>{@code
 * File arquivo = new File("/caminho/relatorio.pdf");
 * String link = LancarRelatorioHelper.lancarRelatorio(arquivo, "relatorio.pdf");
 * }</pre>
 */
public class LancarRelatorioHelper {
    private LancarRelatorioHelper() {
        // Construtor privado para evitar instanciamento
    }

    /*
    exemplo
        File arquivo = new File("/home/mgeweb/repositorio/Sistema/Anexos/Parceiro/735fb8c42bd3e41d3f2784953eec0081");
        if (arquivo.exists()) {
            msg = LancarRelatorioHelper.lancarRelatorio(arquivo, "nomearquivo");
            //msg = LancarRelatorioHelper.lancarRelatorio(arquivo, "nomearquivo", LancarRelatorioHelper.MimeType.PDF.getMimeType());
            ctx.setMensagemRetorno(msg);
        }
     */

    /**
     * Lança um relatório detectando automaticamente o MIME type do arquivo.
     *
     * @param arquivo          Arquivo físico a ser carregado.
     * @param nomeArquivoFinal Nome final que será exibido e armazenado.
     * @return String contendo o link HTML para visualização do relatório.
     * @throws IOException Caso ocorra erro de leitura do arquivo.
     */
    public static String lancarRelatorio(File arquivo, String nomeArquivoFinal) throws IOException {
        String mimeType = getMimeType(arquivo, nomeArquivoFinal);
        return lancarRelatorio(FileUtils.readFileToByteArray(arquivo), nomeArquivoFinal, mimeType);
    }

    /**
     * Lança um relatório quando já se conhece o MIME type previamente.
     *
     * @param arquivo          Arquivo físico a ser carregado.
     * @param nomeArquivoFinal Nome final que será exibido e armazenado.
     * @param mimeType         MIME type do arquivo (ex: "application/pdf").
     * @return String contendo o link HTML para visualização do relatório.
     * @throws IOException Caso ocorra erro de leitura do arquivo.
     */
    public static String lancarRelatorio(File arquivo, String nomeArquivoFinal, String mimeType) throws IOException {
        return lancarRelatorio(FileUtils.readFileToByteArray(arquivo), nomeArquivoFinal, mimeType);
    }

    /**
     * Cria um arquivo de sessão no Sankhya OM e retorna o link de visualização.
     *
     * @param arquivo          Conteúdo binário do arquivo.
     * @param nomeArquivoFinal Nome final que será exibido e armazenado.
     * @param mimeType         MIME type do arquivo.
     * @return Link HTML pronto para visualização.
     * @throws IOException Caso ocorra erro ao criar a sessão do arquivo.
     */
    private static String lancarRelatorio(byte[] arquivo, String nomeArquivoFinal, String mimeType) throws IOException {
        String chaveSessaoArquivo = UIDGenerator.getNextID() + "_" + nomeArquivoFinal;
        SessionFile fileSession = SessionFile.createSessionFile(nomeArquivoFinal.toLowerCase(), mimeType, arquivo);
        ServiceContext.getCurrent().putHttpSessionAttribute(chaveSessaoArquivo, fileSession);
        return getLinkRelatorio("Clique aqui para visualizar.", chaveSessaoArquivo);
    }

    /**
     * Gera o link HTML para abrir o relatório em nova aba.
     *
     * @param descricao Texto a ser exibido no link.
     * @param chave     Identificador da sessão do arquivo.
     * @return Link HTML formatado.
     */
    private static String getLinkRelatorio(final String descricao, final String chave) {
        return "<a title=\"Abrir Arquivo\" href=\"/mge/visualizadorArquivos.mge?chaveArquivo=" + chave
            + "\" target=\"_blank\"><u><b>" + descricao + "</b></u></a>";
    }

    /**
     * Detecta o MIME type de um arquivo utilizando {@link Files#probeContentType(java.nio.file.Path)}.
     * Caso não seja possível detectar, usa fallback pelo {@link MimeType}.
     *
     * @param file     Arquivo físico.
     * @param fileName Nome do arquivo (usado como fallback).
     * @return MIME type correspondente, ou "application/octet-stream" se não reconhecido.
     */
    private static String getMimeType(File file, String fileName) {
        try {
            String type = Files.probeContentType(file.toPath());
            if (type != null) {
                return type;
            }
        } catch (Exception ignored) {
        }
        return MimeType.fromFileName(fileName);
    }

    /**
     * Enum que mapeia extensões conhecidas para seus respectivos MIME types.
     * <p>Usado como fallback quando a detecção automática não funciona.</p>
     */
    public enum MimeType {
        PDF("pdf", "application/pdf"),
        TXT("txt", "text/plain"),
        CSV("csv", "text/csv"),
        XML("xml", "application/xml"),
        JSON("json", "application/json"),
        JPG("jpg", "image/jpeg"),
        JPEG("jpeg", "image/jpeg"),
        PNG("png", "image/png"),
        GIF("gif", "image/gif"),
        DOC("doc", "application/msword"),
        DOCX("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
        XLS("xls", "application/vnd.ms-excel"),
        XLSX("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
        ZIP("zip", "application/zip");

        private final String extension;
        private final String mimeType;

        MimeType(String extension, String mimeType) {
            this.extension = extension;
            this.mimeType = mimeType;
        }

        /**
         * Obtém a extensão do arquivo associada a este MIME type.
         *
         * @return Extensão (sem ponto).
         */
        public String getExtension() {
            return extension;
        }

        /**
         * Obtém o MIME type associado à extensão.
         *
         * @return MIME type correspondente.
         */
        public String getMimeType() {
            return mimeType;
        }

        /**
         * Resolve o MIME type a partir de uma extensão.
         *
         * @param ext Extensão do arquivo (ex: "pdf").
         * @return MIME type correspondente ou "application/octet-stream" se não reconhecido.
         */
        public static String fromExtension(String ext) {
            if (ext == null) {
                return "application/octet-stream";
            }
            String cleanExt = ext.toLowerCase();
            for (MimeType mt : values()) {
                if (mt.extension.equals(cleanExt)) {
                    return mt.mimeType;
                }
            }
            return "application/octet-stream"; // default
        }

        /**
         * Resolve o MIME type a partir do nome de arquivo.
         *
         * @param fileName Nome do arquivo (ex: "relatorio.pdf").
         * @return MIME type correspondente ou "application/octet-stream" se não reconhecido.
         */
        public static String fromFileName(String fileName) {
            if (fileName == null || !fileName.contains(".")) {
                return "application/octet-stream";
            }
            String ext = fileName.substring(fileName.lastIndexOf('.') + 1);
            return fromExtension(ext);
        }
    }
}
