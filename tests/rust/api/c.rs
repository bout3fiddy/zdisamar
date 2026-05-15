use std::ptr;

use zdisamar::api::c::{zds_context_create, zds_context_destroy, zds_default_o2a_input_json};

const OK: i32 = 0;

#[test]
fn c_api_default_o2a_json_reports_required_buffer_and_nul_terminates() {
    let ctx = zds_context_create();
    assert!(!ctx.is_null());

    let mut len = 0_usize;
    assert_eq!(
        unsafe { zds_default_o2a_input_json(ctx, ptr::null_mut(), 0, &mut len) },
        OK
    );
    assert!(len > 0);

    let mut buffer = vec![0_u8; len + 1];
    assert_eq!(
        unsafe { zds_default_o2a_input_json(ctx, buffer.as_mut_ptr(), buffer.len(), &mut len) },
        OK
    );
    assert_eq!(buffer[len], 0);
    assert!(
        std::str::from_utf8(&buffer[..len])
            .unwrap()
            .contains("o2a_disamar_reference_python")
    );

    unsafe {
        zds_context_destroy(ctx);
    }
}
