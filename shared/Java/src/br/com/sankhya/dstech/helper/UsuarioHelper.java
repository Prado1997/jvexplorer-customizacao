package br.com.sankhya.dstech.helper;

import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.jape.wrapper.JapeFactory;
import br.com.sankhya.jape.wrapper.JapeWrapper;
import br.com.sankhya.modelcore.MGEModelException;
import br.com.sankhya.modelcore.util.DynamicEntityNames;

import java.math.BigDecimal;

/**
 * Classe utilitária para operações relacionadas ao usuario.
 * <p>
 * Não pode ser instanciada.
 */
public class UsuarioHelper {

    /**
     * Construtor privado para evitar instanciação.
     *
     * @throws UnsupportedOperationException sempre que chamado.
     */
    private UsuarioHelper() {
        throw new UnsupportedOperationException("Não é permitido instanciar UsuarioHelper");
    }

    public static DynamicVO getUserVO(BigDecimal codUsu) throws Exception {
        try {
            JapeWrapper userDAO = JapeFactory.dao(DynamicEntityNames.USUARIO);
            DynamicVO retVO = userDAO.findByPK(codUsu);

            if(retVO != null) return retVO;

        } catch (Exception e) {
            MGEModelException.throwMe(e);
        }
        throw new MGEModelException("Cod. Usuario " + codUsu + " não encontrado");
    }
}