trigger AddContactRoles on Opportunity (after insert, after update) {
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AddContactRolesHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            AddContactRolesHandler.handleAfterUpdate(Trigger.newMap, Trigger.oldMap);
        }
    }
    
}