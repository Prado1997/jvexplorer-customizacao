package br.com.sankhya.dstech.utils;

import br.com.sankhya.jape.EntityFacade;
import br.com.sankhya.jape.bmp.PersistentLocalEntity;
import br.com.sankhya.jape.core.JapeSession;
import br.com.sankhya.jape.core.JapeSession.SessionHandle;
import br.com.sankhya.jape.core.JapeSession.TXBlock;
import br.com.sankhya.jape.util.FinderWrapper;
import br.com.sankhya.jape.vo.DynamicVO;
import br.com.sankhya.modelcore.util.EntityFacadeFactory;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

public class DwfUtils {

    private DwfUtils() {
        throw new IllegalStateException("Utility class");
    }

    public static DynamicVO findEntityAsVO(String entity, String where, Object[] params) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(entity, where, params);
        Collection entities = dwfFacade.findByDynamicFinderAsVO(wrapper);
        return !entities.isEmpty()?(DynamicVO)entities.iterator().next():null;
    }

    public static Collection<DynamicVO> findEntitysAsVO(String entity, String where, Object[] params) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(entity, where, params);
        Collection entities = dwfFacade.findByDynamicFinderAsVO(wrapper);
        return !entities.isEmpty()?(Collection<DynamicVO>) entities:null;
    }

    public static DynamicVO findEntityAsVO(FinderWrapper wrapper) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        Collection entities = dwfFacade.findByDynamicFinderAsVO(wrapper);
        return !entities.isEmpty()?(DynamicVO)entities.iterator().next():null;
    }

    public static DynamicVO findEntityByPrimaryKeyAsVO(String name, Object key) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        return (DynamicVO)dwfFacade.findEntityByPrimaryKeyAsVO(name, key);
    }

    public static PersistentLocalEntity findEntity(String entity, String where, Object[] params) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(entity, where, params);
        Collection entities = dwfFacade.findByDynamicFinder(wrapper);
        return !entities.isEmpty()?(PersistentLocalEntity)entities.iterator().next():null;
    }

    public static PersistentLocalEntity findEntityByPrimaryKey(String entityName, Object pk) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        return dwfFacade.findEntityByPrimaryKey(entityName, pk);
    }

    public static List<DynamicVO> findEntitiesAsVO(String entity, String where, Object[] params) throws Exception {
        EntityFacade dwfFacade = EntityFacadeFactory.getDWFFacade();
        FinderWrapper wrapper = new FinderWrapper(entity, where, params);
        Collection<DynamicVO> entities = dwfFacade.findByDynamicFinderAsVO(wrapper);
        return (!entities.isEmpty()?new ArrayList<DynamicVO>(entities):new ArrayList<>());
    }

    public static List<DynamicVO> findEntitiesAsVO(String entity) throws Exception {
        return findEntitiesAsVO(entity, "", new Object[0]);
    }

    public static boolean execWithTx(TXBlock txBlock, int priority) throws Exception {
        SessionHandle hnd = null;

        boolean var3;
        try {
            hnd = JapeSession.open();
            hnd.setCanTimeout(false);
            hnd.setPriorityLevel(priority);
            hnd.setFindersMaxRows(-1);
            var3 = hnd.execWithTX(txBlock);
        } finally {
            JapeSession.close(hnd);
        }

        return var3;
    }

    public static boolean execWithTx(TXBlock txBlock) throws Exception {
        return execWithTx(txBlock, JapeSession.NORMAL_PRIORITY);
    }
}
